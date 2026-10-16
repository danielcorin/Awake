import Foundation
import AutomationRuntime
import ServiceManagement

/// Whether macOS opens Awake at login. macOS owns the registration, and the
/// user can change it in System Settings, so Awake reads it back every time
/// rather than keeping its own copy in the TOML file.
public enum LoginItemStatus: String, Sendable {
    case enabled
    case disabled
    /// Registered, but switched off in System Settings > General > Login Items.
    case requiresApproval = "requires-approval"
}

/// The platform seam. The app registers itself with `SMAppService`; tests inject
/// a recording controller so a scenario run never adds a real login item.
public protocol LoginItemController: Sendable {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

public struct SystemLoginItemController: LoginItemController {
    public init() {}

    public var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        // macOS reports `notFound` for an app it has never registered, so it
        // means disabled here; a real failure surfaces when registering.
        case .notRegistered, .notFound: .disabled
        @unknown default: .disabled
        }
    }

    public func register() throws { try SMAppService.mainApp.register() }
    public func unregister() throws { try SMAppService.mainApp.unregister() }

    /// Where the user approves a login item that `requiresApproval`.
    public static func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

/// Deterministic controller for tests and the automation fixture.
public final class RecordingLoginItemController: LoginItemController, @unchecked Sendable {
    private let lock = NSLock()
    private var current: LoginItemStatus
    /// Simulates the user having switched Awake off in System Settings, where
    /// `register()` succeeds but the item stays pending approval.
    private let approvalRequired: Bool

    public init(status: LoginItemStatus = .disabled, approvalRequired: Bool = false) {
        current = status
        self.approvalRequired = approvalRequired
    }

    public var status: LoginItemStatus {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    public func register() throws {
        lock.lock(); defer { lock.unlock() }
        current = approvalRequired ? .requiresApproval : .enabled
    }

    public func unregister() throws {
        lock.lock(); defer { lock.unlock() }
        current = .disabled
    }
}

/// The app's one handle on its login item. The UI, CLI, and HTTP API all
/// change it through the login item operations.
@MainActor
public final class LoginItemStore: LoginItemStoreReadAccess {
    public static let changeNotification = Notification.Name("llc.wvlen.Awake.loginItemChanged")

    private let controller: any LoginItemController

    public init(controller: any LoginItemController = SystemLoginItemController()) {
        self.controller = controller
    }

    public var status: LoginItemStatus { controller.status }

    /// Idempotent: asking for the state it is already in changes nothing.
    @discardableResult
    func setEnabled(_ enabled: Bool) throws -> LoginItemStatus {
        defer { NotificationCenter.default.post(name: Self.changeNotification, object: self) }
        let current = controller.status
        do {
            if enabled, current != .enabled {
                try controller.register()
            } else if !enabled, current == .enabled || current == .requiresApproval {
                try controller.unregister()
            }
        } catch {
            throw LoginItemError.registrationFailed(error.localizedDescription)
        }
        let updated = controller.status
        if enabled, updated == .requiresApproval { throw LoginItemError.requiresApproval }
        return updated
    }
}

/// Implements the login item operations for every interface.
@MainActor
public final class LoginItemOperationService {
    public let store: LoginItemStore

    public init(store: LoginItemStore) {
        self.store = store
    }

    public func loginItemState(_ input: APIInputs.LoginItemState) async throws -> APIData.LoginItemState {
        state(store.status)
    }

    public func loginItemSet(_ input: APIInputs.LoginItemSet) async throws -> APIData.LoginItemState {
        state(try store.setEnabled(input.enabled))
    }

    private func state(_ status: LoginItemStatus) -> APIData.LoginItemState {
        .init(enabled: status == .enabled, status: .init(rawValue: status.rawValue) ?? .disabled)
    }
}

public enum LoginItemError: LocalizedError, Sendable {
    case requiresApproval
    case registrationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .requiresApproval:
            "Allow Awake in System Settings > General > Login Items to open it at login."
        case .registrationFailed(let message):
            "macOS couldn't update Awake's login item: \(message)"
        }
    }
}
