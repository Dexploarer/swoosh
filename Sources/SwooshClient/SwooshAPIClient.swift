// SwooshClient/SwooshAPIClient.swift — URLSession HTTP client for swooshd
//
// Thin client over the SwooshAPI endpoints. Used by the iOS app and any other
// process that wants to talk to a running swooshd without embedding the full
// SwooshKit. Transports JSON, sends a `Bearer` token if one is configured.

import Foundation

/// HTTP client targeting a swooshd instance.
public actor SwooshAPIClient {
    public let baseURL: URL
    public let token: String?
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        baseURL: URL,
        token: String? = nil,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
        self.encoder = JSONEncoder.swooshDefault
        self.decoder = JSONDecoder.swooshDefault
    }

    // MARK: - Endpoints

    /// `GET /health` — returns true if the server responded `200 ok`.
    public func health() async -> Bool {
        let url = baseURL.appendingPathComponent("health")
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
            let body = String(data: data, encoding: .utf8) ?? ""
            return body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ok"
        } catch {
            return false
        }
    }

    /// `GET /api/version` — server build metadata.
    public func version() async throws -> APIVersion {
        let request = try makeRequest(method: "GET", path: "api/version", body: nil)
        return try await execute(request, as: APIVersion.self)
    }

    public func agentStatus() async throws -> AgentStatusResponse {
        let request = try makeRequest(method: "GET", path: "api/agent/status", body: nil)
        return try await execute(request, as: AgentStatusResponse.self)
    }

    public func providers() async throws -> ProvidersResponse {
        let request = try makeRequest(method: "GET", path: "api/providers", body: nil)
        return try await execute(request, as: ProvidersResponse.self)
    }

    public func providerStatus() async throws -> ProviderStatusResponse {
        let request = try makeRequest(method: "GET", path: "api/providers/status", body: nil)
        return try await execute(request, as: ProviderStatusResponse.self)
    }

    public func boardCards() async throws -> BoardCardsResponse {
        let request = try makeRequest(method: "GET", path: "api/board/cards", body: nil)
        return try await execute(request, as: BoardCardsResponse.self)
    }

    public func boardLanes() async throws -> BoardLanesResponse {
        let request = try makeRequest(method: "GET", path: "api/board/lanes", body: nil)
        return try await execute(request, as: BoardLanesResponse.self)
    }

    public func metrics() async throws -> MetricsResponse {
        let request = try makeRequest(method: "GET", path: "api/metrics", body: nil)
        return try await execute(request, as: MetricsResponse.self)
    }

    public func usage() async throws -> UsageResponse {
        let request = try makeRequest(method: "GET", path: "api/usage", body: nil)
        return try await execute(request, as: UsageResponse.self)
    }

    public func skills() async throws -> SkillsResponse {
        let request = try makeRequest(method: "GET", path: "api/skills", body: nil)
        return try await execute(request, as: SkillsResponse.self)
    }

    public func chatAdapters() async throws -> ChatAdaptersResponse {
        let request = try makeRequest(method: "GET", path: "api/chat-adapters", body: nil)
        return try await execute(request, as: ChatAdaptersResponse.self)
    }

    public func setChatAdapter(id: String, enabled: Bool) async throws -> ChatAdaptersResponse {
        let body = try encoder.encode(ChatAdapterToggleRequest(id: id, enabled: enabled))
        let request = try makeRequest(method: "POST", path: "api/chat-adapters/toggle", body: body)
        return try await execute(request, as: ChatAdaptersResponse.self)
    }

    /// `POST /api/agent/chat` — synchronous chat turn. The server runs one
    /// kernel pass and returns the full response in a single HTTP message.
    public func chat(_ chatRequest: ChatRequest) async throws -> ChatResponse {
        let body = try encoder.encode(chatRequest)
        let request = try makeRequest(method: "POST", path: "api/agent/chat", body: body)
        return try await execute(request, as: ChatResponse.self)
    }

    // MARK: - Internals

    private func makeRequest(method: String, path: String, body: Data?) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw SwooshClientError.transport("invalid path: \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
        }
        return request
    }

    private func execute<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SwooshClientError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw SwooshClientError.transport("non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let serverMessage = (try? decoder.decode(APIErrorBody.self, from: data))?.error
                ?? String(data: data, encoding: .utf8)
                ?? ""
            throw SwooshClientError.server(status: http.statusCode, message: serverMessage)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw SwooshClientError.decoding(error.localizedDescription)
        }
    }
}

// MARK: - Errors

public enum SwooshClientError: Error, Sendable, LocalizedError {
    case transport(String)
    case server(status: Int, message: String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .transport(let msg):
            return "Network error: \(msg)"
        case .server(let status, let message):
            return "Server returned \(status): \(message)"
        case .decoding(let msg):
            return "Could not decode server response: \(msg)"
        }
    }
}

// MARK: - JSON defaults

extension JSONEncoder {
    /// JSON encoder configured for the Swoosh wire format (ISO-8601 dates).
    public static let swooshDefault: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    /// JSON decoder configured for the Swoosh wire format (ISO-8601 dates).
    public static let swooshDefault: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
