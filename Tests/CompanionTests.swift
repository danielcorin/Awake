import XCTest
import AutomationRuntime
@testable import AwakeCore

final class CompanionTests: XCTestCase {
    func testConfigurationUsesOneValidatedStore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppConfigurationStore(fileURL: root.appendingPathComponent("config.toml"))
        XCTAssertEqual(try store.load(), .defaults)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        XCTAssertFalse(try store.set(.showWelcomeMessage, value: "false").showWelcomeMessage)
        XCTAssertEqual(try store.entry(for: .showWelcomeMessage).source, .user)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as? Int, 0o600)
        XCTAssertEqual(try store.set(.apiPort, value: "0").apiPort, 0)
        XCTAssertThrowsError(try store.set(.apiHost, value: "0.0.0.0"))
        XCTAssertThrowsError(try store.validate(content: "unknown = true"))
        _ = try store.unset(.apiPort)
        _ = try store.unset(.showWelcomeMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }
    func testTypedConfigurationDispatch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = ConfigurationOperationService(store: .init(fileURL: root.appendingPathComponent("config.toml")))
        let request = AutomationRequest(operation: "configSet", input: .object(["key": .string("show-welcome-message"), "value": .string("false")]))
        let result = try await service.dispatchConfiguration(request)
        XCTAssertEqual(result?.object?["value"], .bool(false))
        XCTAssertTrue(Set(GeneratedCatalog.operations.map(\.id)).isSuperset(of: ["status", "show", "quit", "configSet"]))
    }
    @MainActor
    func testSessionHoldsAndReleasesOnlyTheRequestedAssertions() throws {
        let controller = RecordingPowerAssertionController()
        let store = WakeSessionStore(controller: controller)
        XCTAssertFalse(store.snapshot.active)

        try store.activate(.init(keepDisplayOn: true), durationMinutes: 0)
        XCTAssertEqual(controller.heldKinds, [.keepDisplayOn])
        XCTAssertNil(store.snapshot.expiresAt, "Zero minutes means indefinite")
        XCTAssertNil(store.snapshot.remainingSeconds(at: store.now))

        try store.activate(.init(preventSystemSleep: true, keepDisplayOn: true), durationMinutes: 30)
        XCTAssertEqual(controller.heldKinds, [.preventSystemSleep, .keepDisplayOn])
        XCTAssertEqual(store.snapshot.remainingSeconds(at: store.now), 1800)

        try store.activate(.init(preventSystemSleep: true), durationMinutes: 30)
        XCTAssertEqual(controller.heldKinds, [.preventSystemSleep], "Dropping an assertion releases it")

        store.deactivate()
        XCTAssertTrue(controller.heldKinds.isEmpty)
        XCTAssertFalse(store.snapshot.active)
    }

    @MainActor
    func testSessionRejectsEmptyAndOutOfRangeRequests() throws {
        let controller = RecordingPowerAssertionController()
        let store = WakeSessionStore(controller: controller)
        XCTAssertThrowsError(try store.activate(.none, durationMinutes: 30))
        XCTAssertThrowsError(try store.activate(.init(keepDisplayOn: true), durationMinutes: maximumWakeDurationMinutes + 1))
        XCTAssertThrowsError(try store.activate(.init(keepDisplayOn: true), durationMinutes: -1))
        XCTAssertTrue(controller.heldKinds.isEmpty, "A rejected request holds nothing")
    }

    @MainActor
    func testWakeOperationsFallBackToConfiguredDefaults() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = AppConfigurationStore(fileURL: root.appendingPathComponent("config.toml"))
        _ = try configuration.set(.preventDiskIdle, value: "true")
        _ = try configuration.set(.defaultDurationMinutes, value: "45")
        let service = WakeOperationService(sessions: WakeSessionStore(controller: RecordingPowerAssertionController()),
                                           configuration: configuration)

        let started = try await service.wakeOn(.init())
        XCTAssertTrue(started.active)
        XCTAssertEqual(started.assertions.preventSystemSleep, true)
        XCTAssertEqual(started.assertions.keepDisplayOn, true)
        XCTAssertEqual(started.assertions.preventDiskIdle, true, "A configured default applies when the flag is omitted")
        XCTAssertEqual(started.durationMinutes, 45)
        XCTAssertEqual(started.remainingSeconds, 2700)

        let overridden = try await service.wakeOn(.init(durationMinutes: 0, preventDiskIdle: false))
        XCTAssertEqual(overridden.assertions.preventDiskIdle, false, "An explicit flag beats the default")
        XCTAssertNil(overridden.expiresAt)

        let stopped = try await service.wakeOff(.init())
        XCTAssertFalse(stopped.active)
        XCTAssertEqual(stopped.defaults.preventDiskIdle, true, "Stopping does not change settings")
        let idle = try await service.wakeState(.init())
        XCTAssertFalse(idle.active)
    }

    func testSocketRoundTrip() async throws {
        let root = URL(fileURLWithPath: "/tmp/awake-" + UUID().uuidString)
        let path = root.appendingPathComponent("api.sock").path
        let server = AutomationSocketServer(path: path) { .init(requestId: $0.requestId, data: .string("ok")) }
        try server.start()
        defer { server.stop(); try? FileManager.default.removeItem(at: root) }
        let request = AutomationRequest(operation: "status")
        let response = try await AutomationSocketClient.send(request, path: path)
        XCTAssertEqual(try response.checked(for: request), .string("ok"))
    }
}
