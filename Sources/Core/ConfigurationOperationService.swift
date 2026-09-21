import Foundation
import AutomationRuntime

public actor ConfigurationOperationService: ConfigurationOperations {
    /// The store is a Sendable value; the app and CLI both read it directly.
    public nonisolated let store: AppConfigurationStore
    public init(store: AppConfigurationStore = .init()) { self.store = store }
    private func key(_ value: String) throws -> AppConfigurationKey {
        guard let key = AppConfigurationKey(rawValue: value) else { throw AutomationFailure("invalid_input", "Unknown configuration key '\(value)'. Use config list --all true.") }; return key
    }
    private func wire<T: Encodable, U: Decodable>(_ value: T) throws -> U { try JSONValue.encode(value).decode() }
    private func notify() {
        DistributedNotificationCenter.default().postNotificationName(AppConfigurationStore.changeNotification, object: nil, userInfo: nil, deliverImmediately: true)
    }
    public func configList(_ input: APIInputs.ConfigList) async throws -> APIData.ConfigurationReport {
        try .init(path: store.fileURL.path, entries: wire(store.entries(changesOnly: input.all != true)))
    }
    public func configGet(_ input: APIInputs.ConfigGet) async throws -> APIData.AppConfigurationEntry { try wire(store.entry(for: key(input.key))) }
    public func configSet(_ input: APIInputs.ConfigSet) async throws -> APIData.AppConfigurationEntry {
        let key = try key(input.key); _ = try store.set(key, value: input.value); notify(); return try wire(store.entry(for: key))
    }
    public func configUnset(_ input: APIInputs.ConfigUnset) async throws -> APIData.AppConfigurationEntry {
        let key = try key(input.key); _ = try store.unset(key); notify(); return try wire(store.entry(for: key))
    }
    public func configReload(_ input: APIInputs.ConfigReload) async throws -> APIData.ValidationReport { try store.validate(); notify(); return .init(valid: true) }
    public func configValidate(_ input: APIInputs.ConfigValidate) async throws -> APIData.ValidationReport {
        if let content = input.content { try store.validate(content: content) } else { try store.validate() }; return .init(valid: true)
    }
}

public enum MacAutomationErrors {
    public static func normalize(_ error: Error) -> AutomationFailure {
        if error is AppConfigurationError { return .init("invalid_input", error.localizedDescription) }
        if let wake = error as? WakeSessionError {
            if case .assertionFailed = wake { return .init("capability_unavailable", wake.localizedDescription) }
            return .init("invalid_input", wake.localizedDescription)
        }
        return AutomationFailure.normalize(error)
    }
}
