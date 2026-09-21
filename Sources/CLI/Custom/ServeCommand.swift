import Foundation
import AutomationCLI
import AutomationHTTP
import AwakeCore

struct ServeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "serve", abstract: "Serve the authenticated HTTP API in the foreground. Ctrl-C stops the server and leaves Awake running.")
    @Option(help: "Loopback address: 127.0.0.1 or ::1; defaults to TOML api-host.") var host: String?
    @Option(help: "Port 0...65535; 0 chooses a free port. Defaults to TOML api-port.") var port: Int?
    @Flag(help: "Emit newline-delimited lifecycle events.") var json = false
    func run() async throws {
        let settings = try AppConfigurationStore().load()
        let host = host ?? settings.apiHost, port = port ?? settings.apiPort
        guard ["127.0.0.1", "::1"].contains(host), (0...65535).contains(port) else { throw AutomationFailure("invalid_input", "Use loopback host 127.0.0.1 or ::1 and port 0...65535.") }
        _ = try await AwakeClients.endpoint.handshake(launchIfNeeded: AwakeClients.shouldLaunchApp)
        guard try await AwakeClients.control("$credentialStatus", launch: false).object?["configured"] == .bool(true) else {
            throw AutomationFailure("unauthorized", "Create an API credential first: awake api token create --json")
        }
        let router = Router()
        router.add(middleware: APIGatewayMiddleware { token in
            do { _ = try await AwakeClients.control("$authenticate", input: .object(["token": .string(token)]), launch: false) }
            catch {
                if (error as? AutomationFailure)?.code == "unauthorized" { throw error }
                throw AutomationFailure("unavailable", "The app's credential verifier is unavailable. Open the matching Awake app.")
            }
        })
        router.get("/health") { _, _ in try AutomationHTTPServer.json(["alive": true]) }
        router.get("/ready") { _, _ in
            let info = try await AwakeClients.endpoint.handshake(launchIfNeeded: false)
            return try AutomationHTTPServer.json(OperationResult(requestId: AutomationContext.requestId ?? UUID(), data: info))
        }
        router.get("/openapi.json") { _, _ in
            try AutomationHTTPServer.json(AutomationCoding.decoder.decode(JSONValue.self, from: Data(GeneratedCatalog.openAPI.utf8)))
        }
        router.get("/operations") { _, _ in try AutomationHTTPServer.json(GeneratedCatalog.operations) }
        try GeneratedHTTPBridge(client: AwakeClients.server, transfers: AwakeAutomationPaths.transfers)
            .registerHandlers(on: router, middlewares: [ContractMiddleware(operations: GeneratedCatalog.operations)])
        try AwakeAutomationPaths.transfers.cleanExpired()
        let json = json
        do {
            try await AutomationHTTPServer.run(router: router, host: host, port: port) { actualPort in
                let address = "http://\(host == "::1" ? "[::1]" : host):\(actualPort)"
                if json { try? CLIEnvironment.printJSON(["event": "ready", "address": address]) }
                else { print("Awake API ready at \(address)") }
            }
        } catch { throw AutomationFailure("unavailable", "The HTTP listener could not run. Check that the requested port is free.") }
        if json { try CLIEnvironment.printJSON(["event": "stopped"]) }
        else { print("Awake API stopped.") }
    }
}
