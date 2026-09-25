import Combine
import Foundation
import AutomationRuntime
import AwakeCore

/// The UI's read model for the wake session. It re-reads the app-owned store on
/// every change notification, so a `awake on` from the CLI updates the menu bar
/// exactly like clicking the switch does.
///
/// There is deliberately no timer here: the countdown is derived from
/// `expiresAt` by the view that shows it, so an idle Awake never wakes the CPU.
@MainActor
final class WakeSessionModel: ObservableObject {
    /// The panel and the menu bar click handler drive the same session.
    static let shared = WakeSessionModel()

    @Published private(set) var snapshot: WakeSessionSnapshot = .inactive
    @Published private(set) var sessionError: String?

    private var observer: NSObjectProtocol?

    var isActive: Bool { snapshot.active }

    init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: WakeSessionStore.changeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Human-readable countdown for the moment `date`.
    func summary(at date: Date) -> String {
        guard snapshot.active else { return "Sleeping normally" }
        guard let remaining = snapshot.remainingSeconds(at: date) else { return "Awake until you stop it" }
        return "Awake for another \(Self.duration(remaining))"
    }

    static func duration(_ seconds: Int) -> String {
        let hours = seconds / 3600, minutes = (seconds % 3600) / 60
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(seconds)s"
    }

    func refresh() {
        let latest = AppRuntime.shared.sessions.snapshot
        if latest != snapshot { snapshot = latest }
    }

    func start(minutes: Int? = nil) {
        perform { try await AppRuntime.shared.wakeOn(.init(durationMinutes: minutes)) }
    }

    func stop() {
        perform { try await AppRuntime.shared.wakeOff(.init()) }
    }

    func toggle() { isActive ? stop() : start() }

    /// Called after the assertion defaults change so an already running session
    /// picks them up without losing the time it has left. The assertions are
    /// passed explicitly because the settings write that changed them may not
    /// have reached the TOML file yet.
    func applyDefaultsToActiveSession(_ defaults: WakeAssertionSet) {
        guard snapshot.active else { return }
        guard !defaults.isEmpty else { return stop() }
        let remaining = snapshot.remainingSeconds(at: AppRuntime.shared.sessions.now)
        let minutes = remaining.map { max(1, Int(ceil(Double($0) / 60))) } ?? 0
        perform {
            try await AppRuntime.shared.wakeOn(.init(
                durationMinutes: minutes,
                keepDisplayOn: defaults.keepDisplayOn,
                preventDiskIdle: defaults.preventDiskIdle,
                preventSystemSleep: defaults.preventSystemSleep
            ))
        }
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
