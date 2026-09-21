import Foundation
import AutomationCLI
import AwakeCore

struct ConfigPathCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "config-path", abstract: "Locate the TOML configuration without opening the app.")
    @Flag var json = false
    func run() throws { try CLIEnvironment.printJSON(OperationResult(requestId: UUID(), data: ["path": AppConfigurationStore.defaultFileURL().path]), pretty: !json) }
}

struct APICommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "api", abstract: "Discover the operation contract.", subcommands: [OperationsCommand.self, SchemaCommand.self])
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
}
