import Foundation

/// An immutable view of the wake session. `assertions` lists what is held right
/// now, so an inactive session is simply one that holds nothing.
public struct WakeSessionSnapshot: Equatable, Sendable {
    public var assertions: WakeAssertionSet
    public var durationMinutes: Int?
    public var startedAt: Date?
    public var expiresAt: Date?

    public init(assertions: WakeAssertionSet = .none, durationMinutes: Int? = nil,
                startedAt: Date? = nil, expiresAt: Date? = nil) {
        self.assertions = assertions
        self.durationMinutes = durationMinutes
        self.startedAt = startedAt
        self.expiresAt = expiresAt
    }
    public static let inactive = WakeSessionSnapshot()
    public var active: Bool { !assertions.isEmpty }

    /// Whole seconds left in a timed session, never negative. Nil when the
    /// session is inactive or indefinite.
    public func remainingSeconds(at date: Date) -> Int? {
        guard active, let expiresAt else { return nil }
        return max(0, Int(expiresAt.timeIntervalSince(date).rounded(.up)))
    }
}

/// Owns the process's power assertions. The app holds exactly one of these; the
/// UI, CLI, and HTTP API all reach it through the wake operations.
@MainActor
public final class WakeSessionStore: WakeSessionStoreReadAccess {
    public static let changeNotification = Notification.Name("com.example.Awake.wakeSessionChanged")

    private let controller: any PowerAssertionController
    private let clock: @Sendable () -> Date
    private var tokens: [WakeAssertionKind: UInt32] = [:]
    private var expiryTask: Task<Void, Never>?

    public private(set) var snapshot: WakeSessionSnapshot = .inactive
    public var now: Date { clock() }

    public init(controller: any PowerAssertionController = IOKitPowerAssertionController(),
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.controller = controller
        self.clock = clock
    }

    /// Replaces the held assertions with `assertions`, scheduling an automatic
    /// stop when `durationMinutes` is greater than zero. Any assertion that
    /// macOS refuses is rolled back so the store never reports a partial session.
    @discardableResult
    func activate(_ assertions: WakeAssertionSet, durationMinutes: Int) throws -> WakeSessionSnapshot {
        guard !assertions.isEmpty else { throw WakeSessionError.noAssertionsRequested }
        guard (0...maximumWakeDurationMinutes).contains(durationMinutes) else {
            throw WakeSessionError.invalidDuration(minutes: durationMinutes)
        }
        let reason = "Awake is keeping this Mac awake"
        var acquired: [WakeAssertionKind: UInt32] = [:]
        do {
            for kind in assertions.kinds where tokens[kind] == nil {
                acquired[kind] = try controller.hold(kind, reason: reason)
            }
        } catch {
            acquired.values.forEach(controller.release)
            throw error
        }
        for (kind, token) in tokens where !assertions[kind] {
            controller.release(token)
            tokens[kind] = nil
        }
        tokens.merge(acquired) { current, _ in current }

        let started = clock()
        snapshot = .init(assertions: assertions, durationMinutes: durationMinutes, startedAt: started,
                         expiresAt: durationMinutes > 0 ? started.addingTimeInterval(TimeInterval(durationMinutes) * 60) : nil)
        scheduleExpiry()
        announce()
        return snapshot
    }

    @discardableResult
    func deactivate() -> WakeSessionSnapshot {
        expiryTask?.cancel()
        expiryTask = nil
        tokens.values.forEach(controller.release)
        tokens.removeAll()
        snapshot = .inactive
        announce()
        return snapshot
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        expiryTask = nil
        guard let expiresAt = snapshot.expiresAt else { return }
        let interval = expiresAt.timeIntervalSince(clock())
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, interval)))
            guard !Task.isCancelled else { return }
            self?.deactivate()
        }
    }

    private func announce() {
        NotificationCenter.default.post(name: Self.changeNotification, object: nil)
    }

    deinit {
        expiryTask?.cancel()
        let controller = self.controller
        tokens.values.forEach(controller.release)
    }
}
