import Foundation

/// The public read surface of `WakeSessionStore`. Starting and stopping a
/// session stays internal to Core so every caller goes through an operation.
@MainActor
public protocol WakeSessionStoreReadAccess {
    nonisolated static var changeNotification: Notification.Name { get }
    var snapshot: WakeSessionSnapshot { get }
    var now: Date { get }
}
