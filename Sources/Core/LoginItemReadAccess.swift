import Foundation

/// The public read surface of `LoginItemStore`. Registering and unregistering
/// stay internal to Core so every caller goes through an operation.
@MainActor
public protocol LoginItemStoreReadAccess {
    nonisolated static var changeNotification: Notification.Name { get }
    var status: LoginItemStatus { get }
}
