import Foundation
import AutomationRuntime
import OpenAPIRuntime
import HTTPTypes

public enum HTTPRequestContext {
    @TaskLocal public static var body: JSONValue?
}

/// Capture the original JSON before optional generated DTOs erase null/absent presence.
public struct ContractMiddleware: ServerMiddleware {
    private let operations: [String: OperationDefinition]
    public init(operations: [OperationDefinition]) { self.operations = Dictionary(uniqueKeysWithValues: operations.map { ($0.id, $0) }) }
    public func intercept(_ request: HTTPRequest, body: HTTPBody?, metadata: ServerRequestMetadata, operationID: String,
                          next: @Sendable (HTTPRequest, HTTPBody?, ServerRequestMetadata) async throws -> (HTTPResponse, HTTPBody?)) async throws -> (HTTPResponse, HTTPBody?) {
        do {
            guard let operation = operations[operationID] else { throw AutomationFailure("internal_error", "Missing operation metadata.") }
            // OpenAPI form-style query strings accept '+' for spaces. Normalize only
            // literal query pluses; percent-encoded %2B remains a literal plus.
            var request = request
            if let path = request.path, let separator = path.firstIndex(of: "?") {
                request.path = String(path[...separator]) + path[path.index(after: separator)...].replacingOccurrences(of: "+", with: "%20")
            }
            // Unknown query values must fail consistently with unknown CLI/input-file fields.
            let query = URLComponents(string: request.path ?? "")?.queryItems ?? []
            let known = Set(operation.fields.filter { $0.location == "query" }.map(\.name))
            guard query.allSatisfy({ known.contains($0.name) }), Set(query.map(\.name)).count == query.count else {
                throw AutomationFailure("invalid_input", "Unknown or duplicate query parameter.")
            }
            guard !operation.upload else { return try await next(request, body, metadata) }
            guard let body else { return try await next(request, nil, metadata) }
            var bytes = Data()
            for try await chunk in body {
                guard bytes.count + chunk.count <= 1_048_576 else { throw AutomationFailure("payload_too_large", "JSON bodies are limited to 1 MiB.") }
                bytes.append(contentsOf: chunk)
            }
            if bytes.isEmpty { return try await next(request, HTTPBody(bytes), metadata) }
            let raw = try AutomationCoding.decoder.decode(JSONValue.self, from: bytes)
            guard let values = raw.object else { throw AutomationFailure("invalid_input", "The request body must be a JSON object.") }
            let bodyFields = Set(operation.fields.filter { $0.location == "body" }.map(\.name))
            guard values.keys.allSatisfy({ bodyFields.contains($0) }) else { throw AutomationFailure("invalid_input", "Unknown body field.") }
            return try await HTTPRequestContext.$body.withValue(raw) { try await next(request, HTTPBody(bytes), metadata) }
        } catch {
            let failure: AutomationFailure
            if let error = error as? AutomationFailure { failure = error }
            else { failure = .init("invalid_input", "The request does not match the operation schema.") }
            return (HTTPResponse(status: .init(code: failure.httpStatus), headerFields: [.contentType: "application/json"]),
                    HTTPBody(try AutomationCoding.encoder.encode(OperationError(requestId: AutomationContext.requestId, error: failure))))
        }
    }
}
