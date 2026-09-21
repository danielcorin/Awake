import AutomationCLI
import AwakeCore

/// Add renderers, command replacements, or additional commands in Swift.
enum AwakeCLIStyles {
    static func install(in environment: CLIEnvironment) {
        environment.render(APIOperations.Status.self) { status in
            "\(status.appName) \(status.version) (pid \(status.processIdentifier))"
        }
    }
}
