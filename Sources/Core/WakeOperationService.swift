import Foundation
import AutomationRuntime

/// Implements the wake operations for every interface. The app injects the
/// IOKit controller; the automation fixture injects a recording one.
@MainActor
public final class WakeOperationService {
    public let sessions: WakeSessionStore
    private let configuration: AppConfigurationStore

    public init(sessions: WakeSessionStore, configuration: AppConfigurationStore = .init()) {
        self.sessions = sessions
        self.configuration = configuration
    }

    /// Settings supply every value the caller omits, so `awake on` with no flags
    /// and the menu bar switch start exactly the same session.
    public func resolve(_ input: APIInputs.WakeOn) throws -> (assertions: WakeAssertionSet, durationMinutes: Int) {
        let settings = (try? configuration.load()) ?? .defaults
        var assertions = settings.defaultAssertions
        if let value = input.preventSystemSleep { assertions.preventSystemSleep = value }
        if let value = input.keepDisplayOn { assertions.keepDisplayOn = value }
        if let value = input.preventDiskIdle { assertions.preventDiskIdle = value }
        let minutes = input.durationMinutes ?? settings.defaultDurationMinutes
        guard !assertions.isEmpty else { throw WakeSessionError.noAssertionsRequested }
        guard (0...maximumWakeDurationMinutes).contains(minutes) else { throw WakeSessionError.invalidDuration(minutes: minutes) }
        return (assertions, minutes)
    }

    public func wakeOn(_ input: APIInputs.WakeOn) async throws -> APIData.WakeState {
        let resolved = try resolve(input)
        return state(try sessions.activate(resolved.assertions, durationMinutes: resolved.durationMinutes))
    }

    public func wakeOff(_ input: APIInputs.WakeOff) async throws -> APIData.WakeState {
        state(sessions.deactivate())
    }

    public func wakeState(_ input: APIInputs.WakeState) async throws -> APIData.WakeState {
        state(sessions.snapshot)
    }

    private func state(_ snapshot: WakeSessionSnapshot) -> APIData.WakeState {
        let settings = (try? configuration.load()) ?? .defaults
        return .init(
            active: snapshot.active,
            assertions: .init(snapshot.assertions),
            defaults: .init(settings.defaultAssertions),
            durationMinutes: snapshot.active ? snapshot.durationMinutes : nil,
            startedAt: snapshot.startedAt.map(WakeTimestamp.string),
            expiresAt: snapshot.expiresAt.map(WakeTimestamp.string),
            remainingSeconds: snapshot.remainingSeconds(at: sessions.now)
        )
    }
}

public extension APIData.WakeAssertions {
    init(_ assertions: WakeAssertionSet) {
        self.init(preventSystemSleep: assertions.preventSystemSleep,
                  keepDisplayOn: assertions.keepDisplayOn,
                  preventDiskIdle: assertions.preventDiskIdle)
    }
}

/// Timestamps cross the wire as ISO 8601 strings so every transport agrees.
public enum WakeTimestamp {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    public static func string(_ date: Date) -> String { formatter.string(from: date) }
    public static func date(_ string: String) -> Date? { formatter.date(from: string) }
}
