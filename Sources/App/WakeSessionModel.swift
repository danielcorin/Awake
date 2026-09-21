import Combine
import Foundation
import AutomationRuntime
import AwakeCore

/// The UI's read model for the wake session. It re-reads the app-owned store on
/// every change notification, so a `awake on` from the CLI or the HTTP API
/// updates the menu bar exactly like clicking the switch does.
@MainActor
final class WakeSessionModel: ObservableObject {
    @Published private(set) var snapshot: WakeSessionSnapshot = .inactive
    @Published private(set) var remainingSeconds: Int?
    @Published private(set) var sessionError: String?

    private var observer: NSObjectProtocol?
    private var ticker: Task<Void, Never>?

    var isActive: Bool { snapshot.active }
    var heldTitles: [String] { snapshot.assertions.kinds.map(\.title) }

    init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: WakeSessionStore.changeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.snapshot.expiresAt != nil else { continue }
                self.refresh()
            }
        }
    }

    deinit {
        ticker?.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Human-readable countdown, or the assertions held for an endless session.
    var summary: String {
        guard snapshot.active else { return "Sleeping normally" }
        guard let remainingSeconds else { return "Awake until you stop it" }
        return "Awake for another \(Self.duration(remainingSeconds))"
    }

    static func duration(_ seconds: Int) -> String {
        let hours = seconds / 3600, minutes = (seconds % 3600) / 60
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(seconds)s"
    }

    func refresh() {
        let store = AppRuntime.shared.sessions
        snapshot = store.snapshot
        remainingSeconds = snapshot.remainingSeconds(at: store.now)
    }

    func start(minutes: Int? = nil) {
        perform { try await AppRuntime.shared.wakeOn(.init(durationMinutes: minutes)) }
    }

    func stop() {
        perform { try await AppRuntime.shared.wakeOff(.init()) }
    }

    func toggle() { isActive ? stop() : start() }

    /// Called after the assertion defaults change so an already running session
    /// picks them up without losing the time it has left.
    func applyDefaultsToActiveSession(_ defaults: WakeAssertionSet) {
        guard snapshot.active else { return }
        guard !defaults.isEmpty else { return stop() }
        let indefinite = snapshot.expiresAt == nil
        let minutes = indefinite ? 0 : max(1, Int(ceil(Double(remainingSeconds ?? 60) / 60)))
        perform { try await AppRuntime.shared.wakeOn(.init(durationMinutes: minutes)) }
    }

    private func perform(_ operation: @escaping () async throws -> APIData.WakeState) {
        Task { [weak self] in
            do {
                _ = try await operation()
                self?.sessionError = nil
            } catch {
                self?.sessionError = MacAutomationErrors.normalize(error).message
            }
            self?.refresh()
        }
    }
}
