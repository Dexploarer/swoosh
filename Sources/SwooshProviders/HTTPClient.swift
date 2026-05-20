// SwooshProviders/HTTPClient.swift — 0.9P HTTP Client Abstraction
//
// Real URLSession transport. Mockable for tests.

import Foundation

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

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
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
