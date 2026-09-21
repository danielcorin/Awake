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
            try require(value["entries"].elements.count == 3, "All starter configuration keys")
        },
        .init(APIOperations.ConfigSet.self, input: { .init(key: "show-welcome-message", value: "false") }) { value in
            try require(value["value"] == .bool(false), "Set preference")
        },
        .init(APIOperations.ConfigGet.self, input: { .init(key: "show-welcome-message") }) { value in
            try require(value["value"] == .bool(false), "Read saved preference")
        },
        .init(APIOperations.ConfigValidate.self, input: { .init(content: "api-port = 4321") }) { value in
            try require(value["valid"] == .bool(true), "Validate TOML")
        },
        .init(APIOperations.ConfigValidate.self, error: "invalid_input", input: { .init(content: "api-port = -1") }) { _ in },
        .init(APIOperations.ConfigReload.self, input: { .init() }) { value in
            try require(value["valid"] == .bool(true), "Reload valid settings")
        },
        .init(APIOperations.ConfigUnset.self, input: { .init(key: "show-welcome-message") }) { value in
            try require(value["value"] == .bool(true), "Restore preference default")
        },
    ]
    return try ScenarioSuite(steps: steps, application: application, configuration: configuration, transfers: transfers,
                             normalize: { MacAutomationErrors.normalize($0) })
}
