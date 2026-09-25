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
    private lazy var hotkey = GlobalHotkeyMonitor { WakeSessionModel.shared.toggle() }
    /// Set when the configured shortcut could not be registered.
    private(set) var hotkeyError: String?
    private static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    private lazy var host = AutomationHost(
        version: Self.version,
        operations: GeneratedCatalog.operations.map(\.id),
        normalize: { MacAutomationErrors.normalize($0) }
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
        // Watch settings from launch, not from the first time the panel opens,
        // so a shortcut changed with the CLI registers straight away.
        AppConfigurationModel.shared.start()
        if let settings = try? configuration.store.load() {
            applyHotkey(settings)
            if settings.activateAtLaunch { Task { _ = try? await wakeOn(.init()) } }
        }
    }
    /// Called after any settings reload, so a shortcut changed from the CLI or
    /// by editing the TOML file takes effect without a restart.
    func applyHotkey(_ settings: AppConfiguration) { hotkeyError = hotkey.apply(settings) }
    /// macOS releases a process's power assertions when it exits, so quitting
    /// needs only to close the socket.
    func stop() { server?.stop(); server = nil }
    func status(_ input: APIInputs.Status) async throws -> APIData.AppStatus {
        .init(appName: "Awake", version: Self.version,
              processIdentifier: Int(ProcessInfo.processInfo.processIdentifier), isFrontmost: NSApp.isActive)
    }
    func show(_ input: APIInputs.Show) async throws -> APIData.Message {
        NSApp.unhide(nil)
        statusItem.showPanel()
        return .init(message: "Awake's menu bar panel is open.")
    }
    /// Chrome, not a capability: `status` already reports the version.
    func showAbout() { statusItem.showAbout() }
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
    private var panel: MenuPanel?
    private var outsideClickMonitor: Any?
    private var observers: [NSObjectProtocol] = []

    /// `sun.max.fill` and `moon.zzz` have different glyph bounds (19x18 against
    /// 17x19), so each is centered in one fixed canvas. Without this the button
    /// resizes and the icon visibly shifts every time the session toggles.
    private static let iconWidth = 24.0
    private static let iconCanvas = NSSize(width: 20, height: 20)
    private static let iconConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)

    private static let activeLabel = "Awake is keeping this Mac awake"
    private static let idleLabel = "Awake is idle"
    private static let activeIcon = icon("sun.max.fill", label: activeLabel)
    private static let idleIcon = icon("moon.zzz", label: idleLabel)

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
        item.length = Self.iconWidth
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: WakeSessionStore.changeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        // Dismiss like a menu: anything that takes focus away closes the panel.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePanel() }
        })
        refresh()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    var isPanelVisible: Bool { panel?.isVisible == true }

    /// Drops the panel straight down from the status item, the way a menu does.
    /// An `NSPopover` would draw its caret pointing at the item.
    func showPanel() {
        guard !isPanelVisible else { return }
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.setContentSize(panel.contentView?.fittingSize ?? Self.panelFallbackSize)
        panel.setFrameOrigin(origin(for: panel.frame.size))
        // An accessory app cannot raise a window by activating alone.
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        watchForOutsideClicks()
    }

    private static let panelFallbackSize = NSSize(width: 260, height: 300)
    private static let menuBarGap = 2.0

    private func makePanel() -> MenuPanel {
        // An activating panel is what makes dismissal work: the app becomes
        // active, so losing focus fires `didResignActive`. A non-activating one
        // never activates and would stay on screen after a click elsewhere.
        let panel = MenuPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        // Panels hide on deactivate by default, which for an accessory app
        // means hiding the instant they appear.
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.animationBehavior = .utilityWindow
        panel.contentView = NSHostingView(rootView: MenuPanelContent())
        panel.onCancel = { [weak self] in self?.closePanel() }
        return panel
    }

    /// Aligns under the status item, clamped on screen. A menu bar crowded
    /// enough to hide the item parks it offscreen, so fall back to centering.
    private func origin(for size: NSSize) -> NSPoint {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        guard let button = item.button, let window = button.window,
              NSScreen.screens.contains(where: { $0.frame.intersects(window.frame) }) else {
            return NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height)
        }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let x = min(max(anchor.minX, visible.minX + 8), visible.maxX - size.width - 8)
        return NSPoint(x: x, y: anchor.minY - size.height - Self.menuBarGap)
    }

    private func watchForOutsideClicks() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePanel() }
        }
    }

    /// The standard panel already renders the bundle's icon, name, and version.
    func showAbout() {
        closePanel()
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: "Keeps this Mac awake by holding macOS power assertions.",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    func closePanel() {
        panel?.orderOut(nil)
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    /// Like a menu title, any click on the item while the panel is open just
    /// closes it. Control-click counts as a right-click, as it does everywhere.
    @objc private func clicked() {
        guard !isPanelVisible else { return closePanel() }
        let event = NSApp.currentEvent
        let wantsPanel = event?.type == .rightMouseUp || event?.modifierFlags.contains(.option) == true
            || event?.modifierFlags.contains(.control) == true
        wantsPanel ? showPanel() : WakeSessionModel.shared.toggle()
    }

    private var shownActive: Bool?

    private func refresh() {
        let active = AppRuntime.shared.sessions.snapshot.active
        guard active != shownActive else { return }
        shownActive = active
        item.button?.image = active ? Self.activeIcon : Self.idleIcon
        item.button?.toolTip = "\(active ? Self.activeLabel : Self.idleLabel). Click to toggle, Option-click for options."
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
