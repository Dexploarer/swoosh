// SwooshMCP/MCPClient.swift — 0.8C MCP JSON-RPC client
//
// Speaks JSON-RPC 2.0 over an MCPTransport. Owns the request-id counter,
// the pending-continuation map, and the single reader task that demuxes
// inbound frames into matched responses or notifications.
//
// MCP protocol revision 2025-06-18. Handshake:
//   client → initialize (request)
//   server → initialize result (capabilities, serverInfo, protocolVersion)
//   client → notifications/initialized (notification)
// then tools/list, tools/call, …
//
// Safety: this client is pure transport. It performs NO permission checks
// and NO redaction itself — those belong to MCPServerRegistry / the
// firewall, which the connector layer routes through. The client never
// writes to memory or audit.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Client errors
// ═══════════════════════════════════════════════════════════════════

public enum MCPClientError: Error, Sendable {
    case notInitialized
    case alreadyInitialized
    case transportClosed
    case rpcError(MCPRPCError)
    case decodeFailed(String)
    case protocolMismatch(server: String)
    case timedOut(method: String)
    case connectionLost
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Handshake result
// ═══════════════════════════════════════════════════════════════════

public struct MCPServerHandshake: Sendable, Equatable {
    public let protocolVersion: String
    public let serverName: String
    public let serverVersion: String
    public let hasToolsCapability: Bool
    public let hasResourcesCapability: Bool
    public let hasPromptsCapability: Bool

    public init(protocolVersion: String, serverName: String, serverVersion: String,
                hasToolsCapability: Bool, hasResourcesCapability: Bool, hasPromptsCapability: Bool) {
        self.protocolVersion = protocolVersion
        self.serverName = serverName
        self.serverVersion = serverVersion
        self.hasToolsCapability = hasToolsCapability
        self.hasResourcesCapability = hasResourcesCapability
        self.hasPromptsCapability = hasPromptsCapability
    }
}

/// A tool as returned by `tools/list`.
public struct MCPListedTool: Sendable, Equatable {
    public let name: String
    public let title: String?
    public let description: String?
    /// The tool's JSON Schema for inputs, re-serialized to a string.
    public let inputSchemaJSON: String?

    public init(name: String, title: String? = nil, description: String? = nil,
                inputSchemaJSON: String? = nil) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchemaJSON = inputSchemaJSON
    }
}

/// The result of a `tools/call`.
public struct MCPToolCallResult: Sendable, Equatable {
    /// Concatenated text content blocks. Non-text blocks are summarized.
    public let text: String
    /// True when the server flagged the call as an error result.
    public let isError: Bool

    public init(text: String, isError: Bool) {
        self.text = text
        self.isError = isError
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Client info
// ═══════════════════════════════════════════════════════════════════

public struct MCPClientInfo: Sendable {
    public let name: String
    public let version: String

    public static let swoosh = MCPClientInfo(name: "swoosh", version: "0.8")

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - MCP client
// ═══════════════════════════════════════════════════════════════════

public actor MCPClient {
    private let transport: any MCPTransport
    private let clientInfo: MCPClientInfo
    private let requestTimeout: TimeInterval

    private var nextID = 1
    private var pending: [MCPRequestID: CheckedContinuation<MCPRPCResponse, Error>] = [:]
    private var readerTask: Task<Void, Never>?
    private var started = false
    private var handshakeDone = false
    private var connectionFailure: Error?

    /// Server-initiated notifications observed (method names), for diagnostics.
    private(set) var observedNotifications: [String] = []

    public init(transport: any MCPTransport,
                clientInfo: MCPClientInfo = .swoosh,
                requestTimeout: TimeInterval = 30) {
        self.transport = transport
        self.clientInfo = clientInfo
        self.requestTimeout = requestTimeout
    }

    // ════════════════════════════════════════════════════════════════
    // MARK: - Connection lifecycle
    // ════════════════════════════════════════════════════════════════

    /// Starts the transport and the reader task. Does NOT perform the
    /// handshake — call `initialize()` next.
    public func connect() async throws {
        guard !started else { throw MCPClientError.alreadyInitialized }
        try await transport.start()
        started = true
        let stream = transport.frames()
        readerTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await line in stream {
                    await self.handleFrame(line)
                }
                await self.failAll(MCPClientError.transportClosed)
            } catch {
                await self.failAll(error)
            }
        }
    }

    /// Performs the MCP `initialize` handshake and sends `notifications/initialized`.
    @discardableResult
    public func initialize() async throws -> MCPServerHandshake {
        guard started else { throw MCPClientError.notInitialized }
        guard !handshakeDone else { throw MCPClientError.alreadyInitialized }

        let params: JSONRPCValue = .object([
            "protocolVersion": .string(MCPProtocol.revision),
            "capabilities": .object([:]),  // client advertises no optional capabilities
            "clientInfo": .object([
                "name": .string(clientInfo.name),
                "version": .string(clientInfo.version),
            ]),
        ])

        let response = try await sendRequest(method: "initialize", params: params)
        if let err = response.error { throw MCPClientError.rpcError(err) }
        guard let result = response.result?.objectValue else {
            throw MCPClientError.decodeFailed("initialize result missing")
        }

        let serverProto = result["protocolVersion"]?.stringValue ?? MCPProtocol.revision
        guard MCPProtocol.supportedRevisions.contains(serverProto)
                || serverProto == MCPProtocol.revision else {
            throw MCPClientError.protocolMismatch(server: serverProto)
        }

        let serverInfo = result["serverInfo"]?.objectValue
        let caps = result["capabilities"]?.objectValue ?? [:]
        let handshake = MCPServerHandshake(
            protocolVersion: serverProto,
            serverName: serverInfo?["name"]?.stringValue ?? "unknown",
            serverVersion: serverInfo?["version"]?.stringValue ?? "unknown",
            hasToolsCapability: caps["tools"] != nil,
            hasResourcesCapability: caps["resources"] != nil,
            hasPromptsCapability: caps["prompts"] != nil
        )

        // Complete the handshake.
        try await sendNotification(method: "notifications/initialized", params: nil)
        handshakeDone = true
        return handshake
    }

    /// `tools/list` — discovers the server's tools. Follows `nextCursor`
    /// pagination until the server stops returning one.
    public func listTools() async throws -> [MCPListedTool] {
        try requireHandshake()
        var collected: [MCPListedTool] = []
        var cursor: String? = nil
        repeat {
            var params: [String: JSONRPCValue] = [:]
            if let c = cursor { params["cursor"] = .string(c) }
            let response = try await sendRequest(
                method: "tools/list",
                params: params.isEmpty ? .object([:]) : .object(params)
            )
            if let err = response.error { throw MCPClientError.rpcError(err) }
            guard let result = response.result?.objectValue else {
                throw MCPClientError.decodeFailed("tools/list result missing")
            }
            let rawTools = result["tools"]?.arrayValue ?? []
            for raw in rawTools {
                guard let obj = raw.objectValue, let name = obj["name"]?.stringValue else { continue }
                collected.append(MCPListedTool(
                    name: name,
                    title: obj["title"]?.stringValue,
                    description: obj["description"]?.stringValue,
                    inputSchemaJSON: obj["inputSchema"]?.jsonString()
                ))
            }
            cursor = result["nextCursor"]?.stringValue
        } while cursor != nil
        return collected
    }

    /// `tools/call` — invokes a tool. The result's content blocks are
    /// flattened to text; `isError` is preserved.
    public func callTool(name: String, arguments: [String: JSONRPCValue] = [:]) async throws -> MCPToolCallResult {
        try requireHandshake()
        let params: JSONRPCValue = .object([
            "name": .string(name),
            "arguments": .object(arguments),
        ])
        let response = try await sendRequest(method: "tools/call", params: params)
        if let err = response.error { throw MCPClientError.rpcError(err) }
        guard let result = response.result?.objectValue else {
            throw MCPClientError.decodeFailed("tools/call result missing")
        }
        let isError = result["isError"]?.boolValue ?? false
        let blocks = result["content"]?.arrayValue ?? []
        let text = Self.flattenContent(blocks)
        return MCPToolCallResult(text: text, isError: isError)
    }

    /// Cleanly tears down: cancels the reader, fails any pending requests,
    /// closes the transport.
    public func disconnect() async {
        readerTask?.cancel()
        readerTask = nil
        await transport.close()
        failAll(MCPClientError.transportClosed)
        started = false
        handshakeDone = false
    }

    // ── Diagnostics ───────────────────────────────────────────────

    public var isConnected: Bool { started && connectionFailure == nil }
    public var isReady: Bool { handshakeDone && connectionFailure == nil }
    public func notificationsSeen() -> [String] { observedNotifications }

    // ════════════════════════════════════════════════════════════════
    // MARK: - Request / response plumbing
    // ════════════════════════════════════════════════════════════════

    private func requireHandshake() throws {
        if let failure = connectionFailure { throw failure }
        guard handshakeDone else { throw MCPClientError.notInitialized }
    }

    /// Sends a request and awaits the correlated response.
    private func sendRequest(method: String, params: JSONRPCValue?) async throws -> MCPRPCResponse {
        if let failure = connectionFailure { throw failure }
        guard started else { throw MCPClientError.notInitialized }

        let id = MCPRequestID.int(nextID)
        nextID += 1
        let request = MCPRPCRequest(id: id, method: method, params: params)
        let line = try encode(request)

        return try await withThrowingTaskGroup(of: MCPRPCResponse.self) { group in
            // The actual RPC. Capture `self` weakly inside the inner Task so
            // we can resume the continuation with `.connectionLost` if the
            // actor is deallocated mid-request — otherwise the continuation
            // would leak (never resumed) on actor teardown.
            group.addTask {
                return try await withCheckedThrowingContinuation { cont in
                    Task { [weak self] in
                        guard let self else {
                            cont.resume(throwing: MCPClientError.connectionLost)
                            return
                        }
                        await self.registerAndSend(id: id, line: line, continuation: cont)
                    }
                }
            }
            // Timeout guard.
            let timeout = requestTimeout
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw MCPClientError.timedOut(method: method)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw MCPClientError.connectionLost
            }
            return first
        }
    }

    /// Registers the continuation under `id`, then writes the frame. If the
    /// write fails the continuation is resumed with the error immediately.
    private func registerAndSend(id: MCPRequestID, line: String,
                                 continuation: CheckedContinuation<MCPRPCResponse, Error>) async {
        if let failure = connectionFailure {
            continuation.resume(throwing: failure)
            return
        }
        pending[id] = continuation
        do {
            try await transport.send(line)
        } catch {
            if let cont = pending.removeValue(forKey: id) {
                cont.resume(throwing: error)
            }
        }
    }

    private func sendNotification(method: String, params: JSONRPCValue?) async throws {
        let note = MCPRPCNotification(method: method, params: params)
        try await transport.send(try encode(note))
    }

    // ── Inbound frame handling ────────────────────────────────────

    private func handleFrame(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        guard let frame = try? JSONDecoder().decode(MCPRPCResponse.self, from: data) else {
            // Not a JSON-RPC frame we understand — ignore (servers may log stray text).
            return
        }
        if frame.isResponse, let id = frame.id {
            if let cont = pending.removeValue(forKey: id) {
                cont.resume(returning: frame)
            }
            // Unknown id → drop (late response after timeout).
        } else if frame.isNotification, let method = frame.method {
            observedNotifications.append(method)
            // Server-initiated notifications (e.g. tools/list_changed) are
            // observed but not acted on by this transport-only layer.
        } else if frame.isServerRequest, let id = frame.id {
            // Server→client request (sampling/elicitation/roots). We declared
            // no such capabilities, so reply with method-not-found.
            Task { await self.replyMethodNotFound(to: id) }
        }
    }

    private func replyMethodNotFound(to id: MCPRequestID) async {
        let err = MCPRPCError(code: MCPRPCError.methodNotFound,
                              message: "client does not implement this method")
        // Encode a JSON-RPC error response manually.
        let payload: [String: JSONRPCValue] = [
            "jsonrpc": .string(MCPProtocol.jsonrpcVersion),
            "id": id.asJSONRPCValue,
            "error": .object([
                "code": .int(err.code),
                "message": .string(err.message),
            ]),
        ]
        if let data = try? JSONEncoder().encode(JSONRPCValue.object(payload)),
           let line = String(data: data, encoding: .utf8) {
            try? await transport.send(line)
        }
    }

    /// Fails every pending request — used on transport close / process exit.
    private func failAll(_ error: Error) {
        if connectionFailure == nil { connectionFailure = error }
        let waiting = pending
        pending.removeAll()
        for (_, cont) in waiting {
            cont.resume(throwing: error)
        }
    }

    // ── Encoding ──────────────────────────────────────────────────

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard let line = String(data: data, encoding: .utf8) else {
            throw MCPClientError.decodeFailed("frame is not valid UTF-8")
        }
        return line
    }

    // ── Content flattening ────────────────────────────────────────

    static func flattenContent(_ blocks: [JSONRPCValue]) -> String {
        var parts: [String] = []
        for block in blocks {
            guard let obj = block.objectValue else { continue }
            let type = obj["type"]?.stringValue ?? "unknown"
            switch type {
            case "text":
                parts.append(obj["text"]?.stringValue ?? "")
            case "image":
                let mime = obj["mimeType"]?.stringValue ?? "image"
                parts.append("[image: \(mime)]")
            case "audio":
                let mime = obj["mimeType"]?.stringValue ?? "audio"
                parts.append("[audio: \(mime)]")
            case "resource":
                let uri = obj["resource"]?.objectValue?["uri"]?.stringValue ?? "resource"
                parts.append("[embedded resource: \(uri)]")
            default:
                parts.append("[\(type) content]")
            }
        }
        return parts.joined(separator: "\n")
    }
}

// ── Helpers ───────────────────────────────────────────────────────

private extension MCPRequestID {
    var asJSONRPCValue: JSONRPCValue {
        switch self {
        case .int(let i): return .int(i)
        case .string(let s): return .string(s)
        }
    }
}
