import AppKit
import AwakeCore
import AutomationRuntime
import SwiftUI

@MainActor
final class AppRuntime: ApplicationOperations {
    static let shared = AppRuntime()
    private var server: AutomationSocketServer?
    private let configuration = ConfigurationOperationService()
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
    }
    func stop() { server?.stop(); server = nil }
    func status(_ input: APIInputs.Status) async throws -> APIData.AppStatus {
        .init(appName: "Awake", version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
              processIdentifier: Int(ProcessInfo.processInfo.processIdentifier), isFrontmost: NSApp.isActive)
    }
    func show(_ input: APIInputs.Show) async throws -> APIData.Message {
        NSApp.unhide(nil); NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: \.canBecomeKey)?.makeKeyAndOrderFront(nil)
        return .init(message: "Awake is visible.")
    }
    func quit(_ input: APIInputs.Quit) async throws -> APIData.Message {
        Task { @MainActor in try? await Task.sleep(for: .milliseconds(200)); NSApp.terminate(nil) }
        return .init(message: "Awake is quitting.")
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
    var body: some Scene {
        WindowGroup { ContentView() }.windowResizability(.contentSize)
    }
}
