import Foundation
import AutomationCLI
import AwakeCore

/// Composition and custom presentation are ordinary Swift; generated siblings stay present.
@main
struct AwakeCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        .init(commandName: "awake", abstract: "Control Awake through its app-owned operation service.",
              version: "1.1.0", subcommands: GeneratedCLI.commands + [APICommand.self, ConfigPathCommand.self])
    }
    static func main() async {
        CLIEnvironment.current = CLIEnvironment(client: AwakeClients.local, transfers: AwakeAutomationPaths.transfers)
        AwakeCLIStyles.install(in: CLIEnvironment.current)
        do {
            var command = try parseAsRoot()
            if var async = command as? AsyncParsableCommand { try await async.run() }
            else { try command.run() }
        } catch {
            if error is AutomationFailure || error is AppConfigurationError || error is CocoaError {
                Foundation.exit(CLIEnvironment.report(MacAutomationErrors.normalize(error), json: CommandLine.arguments.contains("--json")))
            }
            if CommandLine.arguments.contains("--json"), exitCode(for: error).rawValue != 0 {
                Foundation.exit(CLIEnvironment.report(AutomationFailure("invalid_input", message(for: error)), json: true))
            }
            exit(withError: error)
        }
    }
}

enum AwakeClients {
    static let endpoint = AppEndpoint(socketPath: AwakeAutomationPaths.socket.path, appName: "Awake", bundleID: "llc.wvlen.Awake")
    static let configuration = ConfigurationOperationService()
    static var shouldLaunchApp: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["APP_AUTOMATION_ROOT"] != nil { return false }
        #endif
        return true
    }
    static let local = AutomationClient { request in
        do {
            if let result = try await configuration.dispatchConfiguration(request) { return .init(requestId: request.requestId, data: result) }
            return try await endpoint.send(request, launchIfNeeded: shouldLaunchApp)
        } catch { throw MacAutomationErrors.normalize(error) }
    }
    static func control(_ operation: String, input: JSONValue = .object([:]), launch: Bool = true) async throws -> JSONValue {
        let request = AutomationRequest(operation: operation, input: input)
        return try await endpoint.send(request, launchIfNeeded: launch).checked(for: request)
    }
}
