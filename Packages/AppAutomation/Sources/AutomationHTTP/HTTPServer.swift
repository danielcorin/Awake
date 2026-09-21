import Foundation
import AutomationRuntime
import Hummingbird
import HummingbirdCore
import Logging
import ServiceLifecycle

private final class RequestLimit: @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0
    func enter() -> Bool { lock.lock(); defer { lock.unlock() }; guard active < 16 else { return false }; active += 1; return true }
    func leave() { lock.lock(); active -= 1; lock.unlock() }
}

public struct APIGatewayMiddleware: RouterMiddleware {
    public typealias Context = BasicRequestContext
    private let authenticate: @Sendable (String) async throws -> Void
    private let limit = RequestLimit()
    public init(authenticate: @escaping @Sendable (String) async throws -> Void) { self.authenticate = authenticate }
    public func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        let requestID = UUID()
        return try await AutomationContext.$requestId.withValue(requestID) {
            do {
                guard limit.enter() else { throw AutomationFailure("busy", "The server is at its request limit.") }
                defer { limit.leave() }
                if !(request.method == .get && request.uri.path == "/health") {
                    guard let authorization = request.headers[.authorization], authorization.hasPrefix("Bearer "), authorization.utf8.count <= 256 else {
                        throw AutomationFailure("unauthorized", "A valid bearer token is required.")
                    }
                    try await authenticate(String(authorization.dropFirst(7)))
                }
                if let length = request.headers[.contentLength].flatMap(Int.init), length > TransferStore.maximumBytes {
                    throw AutomationFailure("payload_too_large", "Request bodies are limited to 25 MiB; JSON is limited to 1 MiB.")
                }
                var response = try await withoutActuallyEscaping(next) { next in
                    try await withThrowingTaskGroup(of: Response.self) { group in
                        group.addTask { try await next(request, context) }
                        group.addTask {
                            try await Task.sleep(for: .seconds(90))
                            throw AutomationFailure("outcome_unknown", "The request deadline expired. A dispatched mutation may have completed; inspect state before retrying.", details: ["requestId": requestID.uuidString])
                        }
                        defer { group.cancelAll() }
                        return try await group.next()!
                    }
                }
                response.headers[.init("X-Request-ID")!] = requestID.uuidString
                response.headers[.cacheControl] = "no-store"
                return response
            } catch {
                let failure: AutomationFailure
                if let error = error as? HTTPError { failure = .init(error.status == .notFound ? "not_found" : "invalid_input", "The HTTP request could not be handled.") }
                else { failure = AutomationFailure.normalize(error) }
                var response = try AutomationHTTPServer.json(OperationError(requestId: requestID, error: failure), status: .init(code: failure.httpStatus))
                response.headers[.init("X-Request-ID")!] = requestID.uuidString
                response.headers[.connection] = "close"
                if failure.code == "unauthorized" { response.headers[.wwwAuthenticate] = "Bearer" }
                return response
            }
        }
    }
}

public enum AutomationHTTPServer {
    public static func json<T: Encodable>(_ value: T, status: HTTPResponse.Status = .ok) throws -> Response {
        Response(status: status, headers: [.contentType: "application/json", .cacheControl: "no-store"],
                 body: .init(byteBuffer: .init(bytes: try AutomationCoding.encoder.encode(value))))
    }
    public static func run(router: Router<BasicRequestContext>, host: String, port: Int,
                           onReady: @escaping @Sendable (Int) -> Void) async throws {
        guard ["127.0.0.1", "::1"].contains(host), (0...65535).contains(port) else {
            throw AutomationFailure("invalid_input", "Serve requires loopback host 127.0.0.1 or ::1 and port 0...65535.")
        }
        var logger = Logger(label: "AppAutomation.HTTP") { StreamLogHandler.standardError(label: $0) }
        logger.logLevel = .warning
        let app = Application(router: router,
            server: .http1(configuration: .init(idleTimeout: .seconds(15), httpDecoderConfiguration: .init(maxHeaderFieldSize: 8192, maxHeaderListSize: 16384, maxHeaderFieldCount: 64))),
            configuration: .init(address: .hostname(host, port: port), availableConnectionsDelegate: MaximumAvailableConnections(64)),
            onServerRunning: { channel in onReady(channel.localAddress?.port ?? port) }, logger: logger)
        var configuration = ServiceGroupConfiguration(services: [app], gracefulShutdownSignals: [.sigint, .sigterm], logger: logger)
        configuration.maximumGracefulShutdownDuration = .seconds(15)
        configuration.maximumCancellationDuration = .seconds(5)
        try await ServiceGroup(configuration: configuration).run()
    }
}
