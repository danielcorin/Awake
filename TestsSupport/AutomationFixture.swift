import Foundation
import AutomationRuntime
import AwakeCore

/// An isolated backend for CLI/HTTP integration. This tool is never bundled or installed.
@main
struct AutomationFixture {
    @MainActor static func main() async throws {
        guard (2...3).contains(CommandLine.arguments.count), CommandLine.arguments[1].hasPrefix("/private/tmp/") || CommandLine.arguments[1].hasPrefix("/tmp/") else {
            fatalError("Supply an isolated /tmp directory")
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let config = ConfigurationOperationService(store: AppConfigurationStore(fileURL: root.appendingPathComponent("config/awake/config.toml")))
        let application = FixtureApplication(configuration: config.store)
        let transfers = TransferStore(directory: root.appendingPathComponent("Transfers"))
        let suite = CommandLine.arguments.last == "--scenarios" ? try appScenarios(application: application, configuration: config, transfers: transfers) : nil
        let credentials = FixtureCredentials()
        let host = AutomationHost(version: "fixture", operations: GeneratedCatalog.operations.map(\.id), credentials: credentials,
                                  normalize: { MacAutomationErrors.normalize($0) }) { request in
            if let value = try await suite?.handle(request) { return value }
            if let value = try await config.dispatchConfiguration(request) { return value }
            return try await application.dispatchApplication(request)
        }
        let server = AutomationSocketServer(path: root.appendingPathComponent("automation.sock").path) { await host.handle($0) }
        try server.start()
        defer { server.stop() }
        FileHandle.standardOutput.write(Data("ready\n".utf8))
        while !Task.isCancelled { try await Task.sleep(for: .seconds(30)) }
    }
}

private final class FixtureCredentials: CredentialAuthority, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    func read() throws -> String? { lock.lock(); defer { lock.unlock() }; return token }
    func create(replace: Bool) throws -> String {
        lock.lock(); defer { lock.unlock() }
        if !replace, let token { return token }
        let value = UUID().uuidString; token = value; return value
    }
    func revoke() throws { lock.lock(); defer { lock.unlock() }; token = nil }
    func authenticate(_ candidate: String) throws -> Bool { try read() == candidate }
}

@MainActor
private final class FixtureApplication: ApplicationOperations {
    /// The wake operations run their real logic here; only the IOKit call is
    /// swapped for a recorder, so a scenario run never keeps this Mac awake.
    private let wake: WakeOperationService

    init(configuration: AppConfigurationStore) {
        wake = WakeOperationService(sessions: WakeSessionStore(controller: RecordingPowerAssertionController()),
                                    configuration: configuration)
    }
    func status(_ input: APIInputs.Status) async throws -> APIData.AppStatus {
        .init(appName: "Awake fixture", version: "fixture", processIdentifier: Int(ProcessInfo.processInfo.processIdentifier), isFrontmost: false)
    }
    func show(_ input: APIInputs.Show) async throws -> APIData.Message {
        throw AutomationFailure("capability_unavailable", "Window activation requires the signed app.")
    }
    func quit(_ input: APIInputs.Quit) async throws -> APIData.Message {
        throw AutomationFailure("capability_unavailable", "App termination requires the signed app.")
    }
    func wakeOn(_ input: APIInputs.WakeOn) async throws -> APIData.WakeState { try await wake.wakeOn(input) }
    func wakeOff(_ input: APIInputs.WakeOff) async throws -> APIData.WakeState { try await wake.wakeOff(input) }
    func wakeState(_ input: APIInputs.WakeState) async throws -> APIData.WakeState { try await wake.wakeState(input) }
}
