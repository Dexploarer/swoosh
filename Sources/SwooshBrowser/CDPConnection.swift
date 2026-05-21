// SwooshBrowser/CDPConnection.swift — Chrome DevTools Protocol connection
//
// WebSocket client for CDP. Sends JSON-RPC commands and receives events
// from a Chrome/Chromium instance running with --remote-debugging-port.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - CDP message types
// ═══════════════════════════════════════════════════════════════════

/// A CDP JSON-RPC request.
public struct CDPRequest: Codable, Sendable {
    public let id: Int
    public let method: String
    public let params: [String: AnyCodableValue]?

    public init(id: Int, method: String, params: [String: AnyCodableValue]? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }
}

/// A CDP JSON-RPC response.
public struct CDPResponse: Codable, Sendable {
    public let id: Int?
    public let result: [String: AnyCodableValue]?
    public let error: CDPError?
    public let method: String?               // For events
    public let params: [String: AnyCodableValue]?  // Event params
}

/// A CDP error.
public struct CDPError: Codable, Sendable {
    public let code: Int
    public let message: String
}

/// Type-erased Codable value for CDP's dynamic JSON.
public enum AnyCodableValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([AnyCodableValue])
    case object([String: AnyCodableValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if container.decodeNil() { self = .null }
        else if let v = try? container.decode([AnyCodableValue].self) { self = .array(v) }
        else if let v = try? container.decode([String: AnyCodableValue].self) { self = .object(v) }
        else { self = .null }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v):    try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v):   try container.encode(v)
        case .null:          try container.encodeNil()
        case .array(let v):  try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }

    /// Extract string value.
    public var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    /// Extract int value.
    public var intValue: Int? {
        if case .int(let v) = self { return v }
        return nil
    }

    /// Extract bool value.
    public var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - CDP connection
// ═══════════════════════════════════════════════════════════════════

/// The CDP transport surface a `CDPBrowserSession` depends on.
///
/// Extracted so sessions can be tested against a mock transport without
/// subclassing the `actor`-based `CDPConnection` (actors cannot be subclassed).
public protocol CDPConnecting: Sendable {
    /// Send a CDP command and wait for the response.
    func send(method: String, params: [String: AnyCodableValue]?) async throws -> CDPResponse
    /// Disconnect the underlying transport.
    func disconnect() async
}

extension CDPConnecting {
    /// Send a parameterless CDP command.
    public func send(method: String) async throws -> CDPResponse {
        try await send(method: method, params: nil)
    }
}

/// WebSocket connection to a Chrome DevTools Protocol endpoint.
public actor CDPConnection: CDPConnecting {
    private let wsURL: URL
    private var webSocket: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private var nextID: Int = 1
    private var pendingRequests: [Int: CheckedContinuation<CDPResponse, Error>] = [:]
    private var eventHandlers: [(String, @Sendable (CDPResponse) -> Void)] = []
    private var isConnected = false

    public init(wsURL: URL) {
        self.wsURL = wsURL
    }

    /// Connect from a Chrome debugging endpoint (http://localhost:9222).
    public static func fromDebugEndpoint(_ endpoint: URL) async throws -> CDPConnection {
        let jsonURL = endpoint.appendingPathComponent("json/version")
        let (data, _) = try await URLSession.shared.data(from: jsonURL)

        struct VersionInfo: Decodable {
            let webSocketDebuggerUrl: String
        }
        let info = try JSONDecoder().decode(VersionInfo.self, from: data)
        guard let wsURL = URL(string: info.webSocketDebuggerUrl) else {
            throw BrowserError.connectionFailed("Invalid WebSocket URL: \(info.webSocketDebuggerUrl)")
        }

        return CDPConnection(wsURL: wsURL)
    }

    /// Open the WebSocket connection.
    public func connect() async throws {
        let ws = session.webSocketTask(with: wsURL)
        ws.resume()
        self.webSocket = ws
        self.isConnected = true
        startReceiving()
    }

    /// Send a CDP command and wait for the response.
    public func send(method: String, params: [String: AnyCodableValue]? = nil) async throws -> CDPResponse {
        guard let ws = webSocket, isConnected else {
            throw BrowserError.connectionFailed("Not connected")
        }

        let id = nextID
        nextID += 1

        let request = CDPRequest(id: id, method: method, params: params)
        let data = try JSONEncoder().encode(request)
        let message = URLSessionWebSocketTask.Message.data(data)
        try await ws.send(message)

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
        }
    }

    /// Register an event handler.
    public func onEvent(_ method: String, handler: @escaping @Sendable (CDPResponse) -> Void) {
        eventHandlers.append((method, handler))
    }

    /// Disconnect.
    public func disconnect() async {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        isConnected = false
    }

    // ── Internal ──

    private func startReceiving() {
        guard let ws = webSocket else { return }
        Task { [weak self] in
            while let self = self {
                do {
                    let message = try await ws.receive()
                    switch message {
                    case .data(let data):
                        await self.handleMessage(data)
                    case .string(let text):
                        if let data = text.data(using: .utf8) {
                            await self.handleMessage(data)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    await self.handleDisconnect()
                    break
                }
            }
        }
    }

    private func handleMessage(_ data: Data) {
        guard let response = try? JSONDecoder().decode(CDPResponse.self, from: data) else { return }

        // Handle responses to pending requests
        if let id = response.id, let continuation = pendingRequests.removeValue(forKey: id) {
            if let error = response.error {
                continuation.resume(throwing: BrowserError.cdpProtocolError(error.code, error.message))
            } else {
                continuation.resume(returning: response)
            }
        }

        // Handle events
        if let method = response.method {
            for (pattern, handler) in eventHandlers where pattern == method {
                handler(response)
            }
        }
    }

    private func handleDisconnect() {
        isConnected = false
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: BrowserError.sessionClosed)
        }
        pendingRequests.removeAll()
    }
}
