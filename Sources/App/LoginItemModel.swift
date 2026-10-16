import Combine
import Foundation
import AutomationRuntime
import AwakeCore

/// The UI's read model for opening at login. It re-reads macOS on every change
/// notification, so `awake login-item set` updates the panel like the switch
/// does, and again whenever the panel opens, since System Settings can change
/// the registration without notifying the app.
@MainActor
final class LoginItemModel: ObservableObject {
    static let shared = LoginItemModel()

    @Published private(set) var status: LoginItemStatus
    @Published private(set) var loginItemError: String?

    private var observer: NSObjectProtocol?

    var isEnabled: Bool { status == .enabled }

    init() {
        status = AppRuntime.shared.loginItems.status
        observer = NotificationCenter.default.addObserver(
            forName: LoginItemStore.changeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func refresh() {
        let latest = AppRuntime.shared.loginItems.status
        if latest != status { status = latest }
        if latest != .requiresApproval, loginItemError != nil { loginItemError = nil }
    }

    func setEnabled(_ enabled: Bool) {
        Task { [weak self] in
            do {
                _ = try await AppRuntime.shared.loginItemSet(.init(enabled: enabled))
                self?.loginItemError = nil
            } catch {
                self?.loginItemError = MacAutomationErrors.normalize(error).message
            }
            self?.refresh()
        }
    }

    func openSystemSettings() { SystemLoginItemController.openSystemSettings() }
}
