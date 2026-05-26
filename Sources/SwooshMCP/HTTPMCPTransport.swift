// SwooshMCP/HTTPMCPTransport.swift — HTTP MCP JSON-RPC transport (0.9S)

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor HTTPMCPTransport: MCPTransport {
    public struct Configuration: Sendable {
        public typealias Sender = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

        public let endpoint: URL
        public let headers: [String: String]
        public let sender: Sender

        public init(
            endpoint: URL,
            headers: [String: String] = [:],
            sender: Sender? = nil
        ) {
            self.endpoint = endpoint
            self.headers = headers
            self.sender = sender ?? { request in
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw MCPTransportError.writeFailed("HTTP MCP response was not HTTP")
                }
                return (data, http)
            }
        }
    }

    private let config: Configuration
    private let stream: AsyncThrowingStream<String, Error>
    private let continuation: AsyncThrowingStream<String, Error>.Continuation
    private var started = false
    private var closed = false

    public init(config: Configuration) {
        self.config = config
        var capturedContinuation: AsyncThrowingStream<String, Error>.Continuation?
        self.stream = AsyncThrowingStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation!
    }

    public func start() async throws {
        guard !started else { throw MCPTransportError.alreadyConnected }
        guard !closed else { throw MCPTransportError.closed }
        started = true
    }

    public func send(_ line: String) async throws {
        guard started, !closed else { throw MCPTransportError.notConnected }
        guard !line.contains("\n") else {
            throw MCPTransportError.writeFailed("frame contains embedded newline")
        }
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.httpBody = Data(line.utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        for (field, value) in config.headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let (data, http) = try await config.sender(request)
        guard 200..<300 ~= http.statusCode else {
            throw MCPTransportError.httpStatus(http.statusCode)
        }
        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        for frame in Self.frames(from: data, contentType: contentType) {
            continuation.yield(frame)
        }
    }

    public nonisolated func frames() -> AsyncThrowingStream<String, Error> {
        stream
    }

    public func close() async {
        guard !closed else { return }
        closed = true
        continuation.finish()
    }

    private static func frames(from data: Data, contentType: String) -> [String] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        if contentType.localizedCaseInsensitiveContains("text/event-stream") {
            return text
                .split(separator: "\n")
                .compactMap { line -> String? in
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed.hasPrefix("data:") else { return nil }
                    let value = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                    return value == "[DONE]" || value.isEmpty ? nil : value
                }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? [] : [trimmed]
    }
}
