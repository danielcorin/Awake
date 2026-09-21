import Foundation
import AutomationRuntime
import AwakeCore

/// Add a typed scenario here with each new operation. The coverage gate fails
/// for missing IDs; every assertion runs through direct Swift, CLI, and HTTP.
@MainActor
func appScenarios(application: any ApplicationOperations, configuration: ConfigurationOperationService, transfers: TransferStore) throws -> ScenarioSuite {
    let steps: [ScenarioStep] = [
        .init(APIOperations.Status.self, input: { .init() }) { value in
            try require(value["appName"] == .string("Awake fixture"), "Application identity")
        },
        .init(APIOperations.Show.self, error: "capability_unavailable", input: { .init() }) { _ in },
        .init(APIOperations.Quit.self, error: "capability_unavailable", input: { .init() }) { _ in },
        .init(APIOperations.ConfigList.self, input: { .init(all: true) }) { value in
            try require(value["entries"].elements.count == 8, "All configuration keys")
        },
        .init(APIOperations.WakeState.self, input: { .init() }) { value in
            try require(value["active"] == .bool(false), "No session before one is started")
            try require(value["assertions"]["keepDisplayOn"] == .bool(false), "An idle app holds nothing")
            try require(value["defaults"]["preventSystemSleep"] == .bool(true), "Configured defaults are reported")
            try require(value["defaults"]["preventDiskIdle"] == .bool(false), "Disk idle is off by default")
            try require(value["remainingSeconds"] == .null, "No countdown while idle")
        },
        .init(APIOperations.WakeOn.self, error: "invalid_input",
              input: { .init(keepDisplayOn: false, preventDiskIdle: false, preventSystemSleep: false) }) { _ in },
        .init(APIOperations.WakeOn.self, error: "invalid_input",
              input: { .init(durationMinutes: 5000, keepDisplayOn: true) }) { _ in },
        .init(APIOperations.WakeOn.self,
              input: { .init(durationMinutes: 30, keepDisplayOn: true, preventDiskIdle: true, preventSystemSleep: false) }) { value in
            try require(value["active"] == .bool(true), "Session started")
            try require(value["assertions"]["keepDisplayOn"] == .bool(true), "Requested display assertion is held")
            try require(value["assertions"]["preventDiskIdle"] == .bool(true), "Explicit true overrides a false default")
            try require(value["assertions"]["preventSystemSleep"] == .bool(false), "Explicit false overrides a true default")
            try require(value["durationMinutes"] == .integer(30), "Requested duration")
            try require(value["startedAt"].string != nil, "Start timestamp")
            try require(value["expiresAt"].string != nil, "Expiry timestamp")
            try require((1500...1800).contains(value["remainingSeconds"].integer ?? -1), "Countdown near the full 30 minutes")
        },
        .init(APIOperations.WakeState.self, input: { .init() }) { value in
            try require(value["active"] == .bool(true), "The session outlives the request that started it")
            try require(value["assertions"]["preventDiskIdle"] == .bool(true), "Held assertions are still reported")
            try require((1500...1800).contains(value["remainingSeconds"].integer ?? -1), "Countdown keeps running")
        },
        .init(APIOperations.WakeOff.self, input: { .init() }) { value in
            try require(value["active"] == .bool(false), "Session stopped")
            try require(value["assertions"]["keepDisplayOn"] == .bool(false), "Every assertion released")
            try require(value["assertions"]["preventDiskIdle"] == .bool(false), "Every assertion released")
            try require(value["remainingSeconds"] == .null, "Countdown cleared")
            try require(value["defaults"]["keepDisplayOn"] == .bool(true), "Defaults survive a stopped session")
        },
        .init(APIOperations.ConfigSet.self, input: { .init(key: "keep-display-on", value: "false") }) { value in
            try require(value["value"] == .bool(false), "Turning off a default is persisted")
        },
        .init(APIOperations.ConfigGet.self, input: { .init(key: "keep-display-on") }) { value in
            try require(value["value"] == .bool(false), "Saved default is read back")
        },
        .init(APIOperations.ConfigValidate.self, input: { .init(content: "default-duration-minutes = 120") }) { value in
            try require(value["valid"] == .bool(true), "Validate TOML")
        },
        .init(APIOperations.ConfigValidate.self, error: "invalid_input", input: { .init(content: "default-duration-minutes = 5000") }) { _ in },
        .init(APIOperations.ConfigValidate.self, error: "invalid_input", input: { .init(content: "toggle-hotkey = \"shift+a\"") }) { _ in },
        .init(APIOperations.ConfigReload.self, input: { .init() }) { value in
            try require(value["valid"] == .bool(true), "Reload valid settings")
        },
        .init(APIOperations.ConfigUnset.self, input: { .init(key: "keep-display-on") }) { value in
            try require(value["value"] == .bool(true), "Unsetting restores the built-in default")
        },
    ]
    return try ScenarioSuite(steps: steps, application: application, configuration: configuration, transfers: transfers,
                             normalize: { MacAutomationErrors.normalize($0) })
}

extension JSONValue {
    var integer: Int? { if case .integer(let value) = self { return value }; return nil }
}
