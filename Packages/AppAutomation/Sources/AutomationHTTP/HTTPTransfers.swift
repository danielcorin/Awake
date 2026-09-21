import Foundation
import AutomationRuntime
import OpenAPIRuntime

public extension TransferStore {
    func stage(_ body: HTTPBody, filename: String) async throws -> TransferFile {
        let writer = try await BlockingIO.shared.run { try self.writer(filename: filename) }
        for try await bytes in body {
            try Task.checkCancellation()
            try await BlockingIO.shared.run { try writer.append(Data(bytes)) }
        }
        return try await BlockingIO.shared.run { try writer.finish() }
    }
    func download(_ file: TransferFile) async throws -> HTTPBody {
        let reader = try await BlockingIO.shared.run { try self.reader(file) }
        let stream = AsyncThrowingStream<HTTPBody.ByteChunk, Error>(unfolding: {
            try Task.checkCancellation()
            return try await BlockingIO.shared.run { try reader.next().map { ArraySlice($0) } }
        })
        return HTTPBody(stream, length: .known(Int64(file.byteCount)))
    }
}
