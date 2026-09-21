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
