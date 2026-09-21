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
    private lazy var settingsWindow = SettingsWindowController()
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
        NSApp.unhide(nil); NSApp.activate(ignoringOtherApps: true)
        settingsWindow.present()
        return .init(message: "Awake settings are visible.")
    }
    func quit(_ input: APIInputs.Quit) async throws -> APIData.Message {
        Task { @MainActor in try? await Task.sleep(for: .milliseconds(200)); NSApp.terminate(nil) }
        return .init(message: "Awake is quitting.")
    }
    func wakeOn(_ input: APIInputs.WakeOn) async throws -> APIData.WakeState { try await wake.wakeOn(input) }
    func wakeOff(_ input: APIInputs.WakeOff) async throws -> APIData.WakeState { try await wake.wakeOff(input) }
    func wakeState(_ input: APIInputs.WakeState) async throws -> APIData.WakeState { try await wake.wakeState(input) }
}

/// Awake is a menu-bar app, so the settings window is created on demand rather
/// than by a SwiftUI scene that would open at launch.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func present() {
        if window == nil {
            let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 520, height: 560),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Awake Settings"
            window.isReleasedWhenClosed = false
            window.center()
            window.contentView = NSHostingView(rootView: ContentView())
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { Task { @MainActor in AppRuntime.shared.start() } }
    func applicationWillTerminate(_ notification: Notification) { MainActor.assumeIsolated { AppRuntime.shared.stop() } }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct AwakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = WakeSessionModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(session: session)
        } label: {
            Image(systemName: session.isActive ? "sun.max.fill" : "moon.zzz")
                .accessibilityLabel(session.isActive ? "Awake is keeping this Mac awake" : "Awake is idle")
        }
        .menuBarExtraStyle(.window)
    }
}
