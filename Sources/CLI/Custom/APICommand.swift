import Foundation
import AutomationCLI
import AwakeCore

struct ConfigPathCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "config-path", abstract: "Locate the TOML configuration without opening the app.")
    @Flag var json = false
    func run() throws { try CLIEnvironment.printJSON(OperationResult(requestId: UUID(), data: ["path": AppConfigurationStore.defaultFileURL().path]), pretty: !json) }
}

struct APICommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "api", abstract: "Discover the contract and manage HTTP credentials.", subcommands: [OperationsCommand.self, SchemaCommand.self, TokenCommand.self])
    struct SchemaCommand: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "schema", abstract: "Emit the bundled OpenAPI contract; works offline.")
        @Flag var json = false
        func run() throws { try CLIEnvironment.printJSON(AutomationCoding.decoder.decode(JSONValue.self, from: Data(GeneratedCatalog.openAPI.utf8)), pretty: !json) }
    }
    struct OperationsCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "operations", abstract: "Describe every operation, CLI command, and route; offline by default.")
        @Flag var json = false
        @Flag(help: "Probe the running app without launching it.") var live = false
        func run() async throws {
            var result: [String: JSONValue] = ["operations": try .encode(GeneratedCatalog.operations), "availability": .string("unknown"),
                "cliOnly": .array(["serve", "config-path", "api operations", "api schema", "api token status", "api token create", "api token show", "api token rotate", "api token revoke", "--generate-completion-script"].map(JSONValue.string))]
            if live {
                do { result["backend"] = try await .encode(AwakeClients.endpoint.handshake(launchIfNeeded: false)); result["availability"] = .string("ready") }
                catch { result["availability"] = .string("unavailable"); result["error"] = try .encode(AutomationFailure.normalize(error)) }
            }
            try CLIEnvironment.printJSON(OperationResult(requestId: UUID(), data: JSONValue.object(result)), pretty: !json)
        }
    }
    struct TokenCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "token", abstract: "Manage the app's Keychain bearer credential. Tokens appear only on explicit create/show/rotate.", subcommands: [Status.self, Create.self, Show.self, Rotate.self, Revoke.self])
        static func perform(_ action: String, force: Bool = false, json: Bool) async throws {
            let request = AutomationRequest(operation: "$credential" + action, input: .object(["force": .bool(force)]))
            let value = try await AwakeClients.endpoint.send(request, launchIfNeeded: AwakeClients.shouldLaunchApp).checked(for: request)
            try CLIEnvironment.printJSON(OperationResult(requestId: request.requestId, data: value), pretty: !json)
        }
        struct Status: AsyncParsableCommand { @Flag var json = false; func run() async throws { try await perform("Status", json: json) } }
        struct Create: AsyncParsableCommand { @Flag var json = false; func run() async throws { try await perform("Create", json: json) } }
        struct Show: AsyncParsableCommand { @Flag var json = false; func run() async throws { try await perform("Show", json: json) } }
        struct Rotate: AsyncParsableCommand { @Flag var json = false; @Flag var force = false; func run() async throws { try await perform("Rotate", force: force, json: json) } }
        struct Revoke: AsyncParsableCommand { @Flag var json = false; @Flag var force = false; func run() async throws { try await perform("Revoke", force: force, json: json) } }
    }
}
