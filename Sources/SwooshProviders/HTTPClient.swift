// SwooshProviders/HTTPClient.swift — 0.9Q HTTP Client Abstraction
//
// Real URLSession transport. Mockable for tests. Every outbound request
// flows through a `NetworkPolicy` (default: `AllowAllNetworkPolicy`) so
// the daemon can lock egress down to an allowlist without each provider
// re-implementing the gate.

import Foundation
import SwooshNetworkPolicy

// ═══════════════════════════════════════════════════════════════════
// MARK: - HTTP client protocol
// ═══════════════════════════════════════════════════════════════════

public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
    func sendStreaming(_ request: URLRequest) async throws -> (URLResponse, AsyncThrowingStream<Data, Error>)
}

public struct HTTPResponse: Sendable {
    public let statusCode: Int
    public let data: Data
    public let headers: [String: String]

    public init(statusCode: Int, data: Data, headers: [String: String] = [:]) {
        self.statusCode = statusCode; self.data = data; self.headers = headers
    }
}

public enum HTTPError: Error, Sendable {
    case invalidURL(String)
    case requestFailed(Int, String)
    case networkError(String)
    case decodingError(String)
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - URLSession HTTP client
// ═══════════════════════════════════════════════════════════════════

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession
    private let policy: any NetworkPolicy
    private let purpose: String

    /// - Parameters:
    ///   - session: URLSession to use. Defaults to `.shared`.
    ///   - policy: Per-host egress gate. Defaults to permissive so
    ///     existing callers stay unchanged; the daemon constructs with
    ///     a real `EgressGate` to enforce its allow/deny list.
    ///   - purpose: Short label included in policy decisions and audit
    ///     entries (e.g. `"provider:openai"`, `"rpc:solana"`).
    public init(
        session: URLSession = .shared,
        policy: any NetworkPolicy = AllowAllNetworkPolicy(),
        purpose: String = "http"
    ) {
        self.session = session
        self.policy = policy
        self.purpose = purpose
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        try await preflight(request)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPError.networkError("Not an HTTP response")
        }

        var headers: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            if let k = key as? String, let v = value as? String {
                headers[k] = v
            }
        }

        if httpResponse.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw HTTPError.requestFailed(httpResponse.statusCode, body)
        }

        return HTTPResponse(statusCode: httpResponse.statusCode, data: data, headers: headers)
    }

    public func sendStreaming(_ request: URLRequest) async throws -> (URLResponse, AsyncThrowingStream<Data, Error>) {
        try await preflight(request)
        let (bytes, response) = try await session.bytes(for: request)
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            Task {
                do {
                    for try await line in bytes.lines {
                        continuation.yield(Data(line.utf8))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
        return (response, stream)
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Egress preflight
    // ═══════════════════════════════════════════════════════════════

    private func preflight(_ request: URLRequest) async throws {
        guard let egress = EgressRequest(request: request, purpose: purpose) else {
            // Missing host — let URLSession surface the configuration
            // error; not a policy denial.
            return
        }
        let decision = await policy.evaluate(egress)
        if case let .deny(reason) = decision {
            throw EgressDeniedError(request: egress, reason: reason)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Mock HTTP client (for tests)
// ═══════════════════════════════════════════════════════════════════

public actor MockHTTPClient: HTTPClient {
    private var queuedResponses: [@Sendable (URLRequest) -> HTTPResponse] = []
    private var recorded: [URLRequest] = []

    public init() {}

    public func enqueue(_ handler: @escaping @Sendable (URLRequest) -> HTTPResponse) {
        queuedResponses.append(handler)
    }

    public func enqueueJSON(_ json: String, statusCode: Int = 200) {
        queuedResponses.append { _ in
            HTTPResponse(statusCode: statusCode, data: Data(json.utf8))
        }
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        recorded.append(request)
        if !queuedResponses.isEmpty {
            let handler = queuedResponses.removeFirst()
            return handler(request)
        }
        return HTTPResponse(statusCode: 500, data: Data("No mock response queued".utf8))
    }

    public func sendStreaming(_ request: URLRequest) async throws -> (URLResponse, AsyncThrowingStream<Data, Error>) {
        recorded.append(request)
        let response: HTTPResponse
        if !queuedResponses.isEmpty {
            let handler = queuedResponses.removeFirst()
            response = handler(request)
        } else {
            response = HTTPResponse(statusCode: 500, data: Data("No mock response queued".utf8))
        }
        let url = request.url ?? URL(string: "http://localhost")!
        let http = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        )!
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            if !response.data.isEmpty {
                continuation.yield(response.data)
            }
            continuation.finish()
        }
        return (http, stream)
    }

    public func getRecordedRequests() -> [URLRequest] { recorded }
}
