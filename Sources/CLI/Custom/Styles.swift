import AutomationCLI
import AwakeCore

/// Add renderers, command replacements, or additional commands in Swift.
enum AwakeCLIStyles {
    static func install(in environment: CLIEnvironment) {
        environment.render(APIOperations.Status.self) { status in
            "\(status.appName) \(status.version) (pid \(status.processIdentifier))"
        }
        environment.render(APIOperations.WakeOn.self) { describe($0) }
        environment.render(APIOperations.WakeOff.self) { describe($0) }
        environment.render(APIOperations.WakeState.self) { describe($0) }
    }

    private static func describe(_ state: APIData.WakeState) -> String {
        guard state.active else { return "asleep as usual (defaults: \(list(state.defaults)))" }
        let held = "holding \(list(state.assertions))"
        guard let remaining = state.remainingSeconds else { return "awake indefinitely, \(held)" }
        return "awake for another \(remaining / 60)m \(remaining % 60)s, \(held)"
    }

    private static func list(_ assertions: APIData.WakeAssertions) -> String {
        let names = [
            assertions.preventSystemSleep ? "system" : nil,
            assertions.keepDisplayOn ? "display" : nil,
            assertions.preventDiskIdle ? "disk" : nil,
        ].compactMap { $0 }
        return names.isEmpty ? "nothing" : names.joined(separator: "+")
    }
}
