import AppKit
import AwakeCore
import AutomationRuntime
import SwiftUI

@MainActor
final class AppRuntime: ApplicationOperations {
    static let shared = AppRuntime()
    private var server: AutomationSocketServer?
    private let configuration = ConfigurationOperationService()
    let sessions = WakeSessionStore()
    private lazy var wake = WakeOperationService(sessions: sessions, configuration: configuration.store)
    private lazy var statusItem = StatusItemController()
    private lazy var host = AutomationHost(
        version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
        operations: GeneratedCatalog.operations.map(\.id),
        credentials: KeychainCredentialStore(service: "com.example.Awake.http-api"), normalize: { MacAutomationErrors.normalize($0) }
    ) { [weak self] request in
        guard let self else { throw AutomationFailure("unavailable", "The app is shutting down.") }
        if let value = try await self.configuration.dispatchConfiguration(request) { return value }
        return try await self.dispatchApplication(request)
    }
    func start() {
        guard server == nil else { return }
        _ = statusItem
        let server = AutomationSocketServer(path: AwakeAutomationPaths.socket.path) { await AppRuntime.shared.host.handle($0) }
        do { try AwakeAutomationPaths.transfers.cleanExpired(); try server.start(); self.server = server }
        catch { NSLog("Automation startup failed: \(error.localizedDescription)") }
        if (try? configuration.store.load())?.activateAtLaunch == true {
            Task { _ = try? await wakeOn(.init()) }
        }
    }
    /// macOS releases a process's power assertions when it exits, so quitting
    /// needs only to close the socket.
    func stop() { server?.stop(); server = nil }
    func status(_ input: APIInputs.Status) async throws -> APIData.AppStatus {
        .init(appName: "Awake", version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
              processIdentifier: Int(ProcessInfo.processInfo.processIdentifier), isFrontmost: NSApp.isActive)
    }
    func show(_ input: APIInputs.Show) async throws -> APIData.Message {
        NSApp.unhide(nil)
        statusItem.showPanel()
        return .init(message: "Awake's menu bar panel is open.")
    }
    func quit(_ input: APIInputs.Quit) async throws -> APIData.Message {
        Task { @MainActor in try? await Task.sleep(for: .milliseconds(200)); NSApp.terminate(nil) }
        return .init(message: "Awake is quitting.")
    }
    func wakeOn(_ input: APIInputs.WakeOn) async throws -> APIData.WakeState { try await wake.wakeOn(input) }
    func wakeOff(_ input: APIInputs.WakeOff) async throws -> APIData.WakeState { try await wake.wakeOff(input) }
    func wakeState(_ input: APIInputs.WakeState) async throws -> APIData.WakeState { try await wake.wakeState(input) }
}

/// The menu bar item. `MenuBarExtra` always opens its content on click, so the
/// status item is AppKit: a plain click toggles the session, and option- or
/// right-click opens the panel.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var fallbackWindow: NSWindow?
    private var observer: NSObjectProtocol?

    /// `sun.max.fill` and `moon.zzz` have different glyph bounds (19x18 against
    /// 17x19), so each is centered in one fixed canvas. Without this the button
    /// resizes and the icon visibly shifts every time the session toggles.
    private static let iconWidth = 24.0
    private static let iconCanvas = NSSize(width: 20, height: 20)
    private static let iconConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)

    private static func icon(_ symbolName: String, label: String) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)?
            .withSymbolConfiguration(iconConfiguration) else { return nil }
        let canvas = iconCanvas
        let image = NSImage(size: canvas, flipped: false) { _ in
            let size = symbol.size
            symbol.draw(in: NSRect(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2,
                                   width: size.width, height: size.height))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = label
        return image
    }

    override init() {
        super.init()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ContentView())
        item.length = Self.iconWidth
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
        }
        observer = NotificationCenter.default.addObserver(
            forName: WakeSessionStore.changeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func showPanel() {
        guard !popover.isShown else { return popover.performClose(nil) }
        // A crowded menu bar parks hidden status items offscreen, where an
        // anchored popover would be drawn off the side. Fall back to a window.
        guard let button = item.button, let frame = button.window?.frame,
              NSScreen.screens.contains(where: { $0.frame.intersects(frame) }) else {
            return presentWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func presentWindow() {
        if fallbackWindow == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Awake"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ContentView())
            window.setContentSize(window.contentView?.fittingSize ?? .init(width: 260, height: 260))
            window.center()
            fallbackWindow = window
        }
        // An accessory app cannot reliably raise a window by activating first.
        fallbackWindow?.level = .floating
        fallbackWindow?.orderFrontRegardless()
        fallbackWindow?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        let wantsPanel = event?.modifierFlags.contains(.option) == true || event?.type == .rightMouseUp
        wantsPanel ? showPanel() : WakeSessionModel.shared.toggle()
    }

    private func refresh() {
        let active = AppRuntime.shared.sessions.snapshot.active
        let label = active ? "Awake is keeping this Mac awake" : "Awake is idle"
        item.button?.image = Self.icon(active ? "sun.max.fill" : "moon.zzz", label: label)
        item.button?.toolTip = "\(label). Click to toggle, Option-click for options."
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { MainActor.assumeIsolated { AppRuntime.shared.start() } }
    func applicationWillTerminate(_ notification: Notification) { MainActor.assumeIsolated { AppRuntime.shared.stop() } }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct AwakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // The menu bar item is the whole interface; this scene stays empty.
    var body: some Scene { Settings { EmptyView() } }
}
