import Foundation
import Darwin
import TOML

/// The longest session Awake will hold, as a safety cap on a forgotten timer.
public let maximumWakeDurationMinutes = 1440

public struct AppConfiguration: Equatable, Sendable {
    public static let defaults = AppConfiguration()
    public var preventSystemSleep: Bool
    public var keepDisplayOn: Bool
    public var preventDiskIdle: Bool
    public var defaultDurationMinutes: Int
    public var activateAtLaunch: Bool
    public var showWelcomeMessage: Bool
    public var apiHost: String
    public var apiPort: Int
    public init(preventSystemSleep: Bool = true, keepDisplayOn: Bool = true, preventDiskIdle: Bool = false,
                defaultDurationMinutes: Int = 0, activateAtLaunch: Bool = false,
                showWelcomeMessage: Bool = true, apiHost: String = "127.0.0.1", apiPort: Int = 8080) {
        self.preventSystemSleep = preventSystemSleep; self.keepDisplayOn = keepDisplayOn
        self.preventDiskIdle = preventDiskIdle; self.defaultDurationMinutes = defaultDurationMinutes
        self.activateAtLaunch = activateAtLaunch
        self.showWelcomeMessage = showWelcomeMessage; self.apiHost = apiHost; self.apiPort = apiPort
    }
    /// The assertions a session holds when the caller does not override them.
    public var defaultAssertions: WakeAssertionSet {
        .init(preventSystemSleep: preventSystemSleep, keepDisplayOn: keepDisplayOn, preventDiskIdle: preventDiskIdle)
    }
}
public enum AppConfigurationKey: String, CaseIterable, Codable, Sendable {
    case preventSystemSleep = "prevent-system-sleep", keepDisplayOn = "keep-display-on", preventDiskIdle = "prevent-disk-idle",
         defaultDurationMinutes = "default-duration-minutes", activateAtLaunch = "activate-at-launch",
         showWelcomeMessage = "show-welcome-message", apiHost = "api-host", apiPort = "api-port"
    public var valueType: String {
        switch self {
        case .defaultDurationMinutes, .apiPort: "integer"
        case .apiHost: "string"
        default: "boolean"
        }
    }
    public var documentation: String {
        switch self {
        case .preventSystemSleep: "Hold PreventUserIdleSystemSleep by default so the Mac does not idle-sleep."
        case .keepDisplayOn: "Hold PreventUserIdleDisplaySleep by default so the display stays on and the screen saver never starts."
        case .preventDiskIdle: "Hold PreventDiskIdle by default so disks are not spun down while idle."
        case .defaultDurationMinutes: "Default session length in minutes from 0 through \(maximumWakeDurationMinutes). Zero stays awake until stopped."
        case .activateAtLaunch: "Start a session automatically when Awake launches."
        case .showWelcomeMessage: "Whether the settings window explains what Awake does."
        case .apiHost: "Loopback API address, 127.0.0.1 or ::1. Restart serve to apply."
        case .apiPort: "API port from 0 through 65535. Zero chooses a free port. Restart serve to apply."
        }
    }
}
public enum AppConfigurationValue: Equatable, Sendable, Codable {
    case boolean(Bool), string(String), integer(Int)
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self) { self = .boolean(v) }
        else if let v = try? c.decode(Int.self) { self = .integer(v) }
        else { self = .string(try c.decode(String.self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .boolean(let v): try c.encode(v); case .string(let v): try c.encode(v); case .integer(let v): try c.encode(v) }
    }
    public var displayValue: String {
        switch self { case .boolean(let v): v ? "true" : "false"; case .string(let v): v; case .integer(let v): String(v) }
    }
}
public enum AppConfigurationSource: String, Codable, Sendable { case defaults, user }
public struct AppConfigurationEntry: Equatable, Sendable, Codable {
    public var key: AppConfigurationKey
    public var value: AppConfigurationValue
    public var source: AppConfigurationSource
    public var documentation: String
}
public enum AppConfigurationError: LocalizedError, Sendable {
    case invalidFile(path: String, reason: String)
    public var errorDescription: String? {
        switch self { case .invalidFile(let path, let reason): "Invalid configuration at \(path): \(reason)" }
    }
}
public struct AppConfigurationStore: Sendable, AppConfigurationStoreReadAccess {
    public static let changeNotification = Notification.Name("com.example.Awake.configurationChanged")
    public let fileURL: URL
    public init(fileURL: URL = Self.defaultFileURL()) { self.fileURL = fileURL }
    public static func defaultFileURL(environment: [String: String] = ProcessInfo.processInfo.environment,
                                     homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        let root = environment["XDG_CONFIG_HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil } ?? homeDirectory.appendingPathComponent(".config")
        return root.appendingPathComponent("awake/config.toml")
    }
    public func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fileURL.deletingLastPathComponent().path)
    }
    private func error(_ reason: String) -> AppConfigurationError { .invalidFile(path: fileURL.path, reason: reason) }
    private func overrides() throws -> [String: AppConfigurationValue] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        do {
            let values = try TOMLDecoder().decode([String: AppConfigurationValue].self, from: Data(contentsOf: fileURL))
            try validate(values); return values
        } catch { throw self.error(error.localizedDescription) }
    }
    private func validate(_ values: [String: AppConfigurationValue]) throws {
        for (raw, value) in values {
            guard let key = AppConfigurationKey(rawValue: raw) else { throw error("Unknown key '\(raw)'.") }
            switch (key, value) {
            case (.preventSystemSleep, .boolean), (.keepDisplayOn, .boolean), (.preventDiskIdle, .boolean),
                 (.activateAtLaunch, .boolean), (.showWelcomeMessage, .boolean): break
            case (.defaultDurationMinutes, .integer(let minutes)) where (0...maximumWakeDurationMinutes).contains(minutes): break
            case (.apiHost, .string(let host)) where ["127.0.0.1", "::1"].contains(host): break
            case (.apiPort, .integer(let port)) where (0...65535).contains(port): break
            default: throw error("Invalid value for \(raw); expected \(key.valueType). \(key.documentation)")
            }
        }
    }
    private func value(_ key: AppConfigurationKey, in config: AppConfiguration = .defaults) -> AppConfigurationValue {
        switch key {
        case .preventSystemSleep: .boolean(config.preventSystemSleep)
        case .keepDisplayOn: .boolean(config.keepDisplayOn)
        case .preventDiskIdle: .boolean(config.preventDiskIdle)
        case .defaultDurationMinutes: .integer(config.defaultDurationMinutes)
        case .activateAtLaunch: .boolean(config.activateAtLaunch)
        case .showWelcomeMessage: .boolean(config.showWelcomeMessage)
        case .apiHost: .string(config.apiHost)
        case .apiPort: .integer(config.apiPort)
        }
    }
    public func load() throws -> AppConfiguration {
        let values = try overrides()
        var configuration = AppConfiguration.defaults
        if case .boolean(let v) = values[AppConfigurationKey.preventSystemSleep.rawValue] { configuration.preventSystemSleep = v }
        if case .boolean(let v) = values[AppConfigurationKey.keepDisplayOn.rawValue] { configuration.keepDisplayOn = v }
        if case .boolean(let v) = values[AppConfigurationKey.preventDiskIdle.rawValue] { configuration.preventDiskIdle = v }
        if case .integer(let v) = values[AppConfigurationKey.defaultDurationMinutes.rawValue] { configuration.defaultDurationMinutes = v }
        if case .boolean(let v) = values[AppConfigurationKey.activateAtLaunch.rawValue] { configuration.activateAtLaunch = v }
        if case .boolean(let v) = values[AppConfigurationKey.showWelcomeMessage.rawValue] { configuration.showWelcomeMessage = v }
        if case .string(let v) = values[AppConfigurationKey.apiHost.rawValue] { configuration.apiHost = v }
        if case .integer(let v) = values[AppConfigurationKey.apiPort.rawValue] { configuration.apiPort = v }
        return configuration
    }
    public func validate() throws { _ = try overrides() }
    public func validate(content: String) throws {
        do { try validate(TOMLDecoder().decode([String: AppConfigurationValue].self, from: Data(content.utf8))) }
        catch { throw self.error(error.localizedDescription) }
    }
    public func entry(for key: AppConfigurationKey) throws -> AppConfigurationEntry {
        let overrides = try overrides()
        return .init(key: key, value: overrides[key.rawValue] ?? value(key), source: overrides[key.rawValue] == nil ? .defaults : .user, documentation: key.documentation)
    }
    public func entries(changesOnly: Bool) throws -> [AppConfigurationEntry] {
        let values = try overrides()
        return AppConfigurationKey.allCases.map { key in
            AppConfigurationEntry(key: key, value: values[key.rawValue] ?? value(key), source: values[key.rawValue] == nil ? .defaults : .user, documentation: key.documentation)
        }.filter { !changesOnly || $0.source == .user }
    }
    @discardableResult func set(_ key: AppConfigurationKey, value text: String) throws -> AppConfiguration {
        let value: AppConfigurationValue
        switch key {
        case .preventSystemSleep, .keepDisplayOn, .preventDiskIdle, .activateAtLaunch, .showWelcomeMessage:
            guard text == "true" || text == "false" else { throw error("Use true or false.") }; value = .boolean(text == "true")
        case .defaultDurationMinutes:
            guard let minutes = Int(text) else { throw error("Use an integer number of minutes.") }; value = .integer(minutes)
        case .apiHost: value = .string(text)
        case .apiPort:
            guard let port = Int(text) else { throw error("Use an integer port.") }; value = .integer(port)
        }
        try validate([key.rawValue: value])
        return try update { $0[key.rawValue] = value == self.value(key) ? nil : value }
    }
    @discardableResult func unset(_ key: AppConfigurationKey) throws -> AppConfiguration { try update { $0[key.rawValue] = nil } }
    private func update(_ change: (inout [String: AppConfigurationValue]) -> Void) throws -> AppConfiguration {
        try prepareDirectory()
        let fd = open(fileURL.deletingLastPathComponent().appendingPathComponent(".config.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw error("Could not open configuration lock.") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw error("Could not lock configuration.") }
        defer { flock(fd, LOCK_UN) }
        var values = try overrides(); change(&values)
        if values.isEmpty {
            if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
        } else {
            let encoder = TOMLEncoder(); encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(values).write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        }
        return try load()
    }
}
