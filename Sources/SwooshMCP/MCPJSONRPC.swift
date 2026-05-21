// SwooshMCP/MCPJSONRPC.swift — 0.8C MCP JSON-RPC 2.0 wire types
//
// JSON-RPC 2.0 framing for the Model Context Protocol stdio transport.
// Targets MCP protocol revision 2025-06-18
// (https://modelcontextprotocol.io/specification/2025-06-18).
//
// Newline-delimited JSON-RPC: each message is a single JSON object on one
// line, no embedded newlines. These types encode/decode that wire format;
// transport (Process/stdio) and correlation live in separate files.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Protocol constants
// ═══════════════════════════════════════════════════════════════════

public enum MCPProtocol {
    /// MCP protocol revision this client targets and advertises in `initialize`.
    /// We speak `2025-06-18` — wire-compatible with the now-stable `2025-11-25`
    /// for the four methods we use (`initialize`, `notifications/initialized`,
    /// `tools/list`, `tools/call`) and the broader deployed-server base. If a
    /// server negotiates `2025-11-25` we accept it (see `supportedRevisions`).
    public static let revision = "2025-06-18"
    /// Revisions this client can accept if a server negotiates a different one.
    /// Newer-than-`revision` entries (`2025-11-25`) are accepted because the
    /// frames we send are unchanged across these revisions; older entries
    /// (`2025-03-26`) are accepted for compatibility.
    public static let supportedRevisions: Set<String> = ["2025-11-25", "2025-06-18", "2025-03-26"]
    public static let jsonrpcVersion = "2.0"
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - JSON-RPC id
// ═══════════════════════════════════════════════════════════════════

/// A JSON-RPC request id. The spec allows string or number; this client
/// always *sends* integers but accepts either when matching responses.
public enum MCPRequestID: Codable, Sendable, Hashable, CustomStringConvertible {
    case int(Int)
    case string(String)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { self = .int(i) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "JSON-RPC id must be int or string")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .int(let i): try c.encode(i)
        case .string(let s): try c.encode(s)
        }
    }

    public var description: String {
        switch self {
        case .int(let i): return String(i)
        case .string(let s): return s
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Outbound request / notification
// ═══════════════════════════════════════════════════════════════════

/// A JSON-RPC 2.0 request: has an id, expects a response.
public struct MCPRPCRequest: Codable, Sendable {
    public let jsonrpc: String
    public let id: MCPRequestID
    public let method: String
    public let params: JSONRPCValue?

    public init(id: MCPRequestID, method: String, params: JSONRPCValue? = nil) {
        self.jsonrpc = MCPProtocol.jsonrpcVersion
        self.id = id
        self.method = method
        self.params = params
    }
}

/// A JSON-RPC 2.0 notification: no id, no response expected.
public struct MCPRPCNotification: Codable, Sendable {
    public let jsonrpc: String
    public let method: String
    public let params: JSONRPCValue?

    public init(method: String, params: JSONRPCValue? = nil) {
        self.jsonrpc = MCPProtocol.jsonrpcVersion
        self.method = method
        self.params = params
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Inbound response
// ═══════════════════════════════════════════════════════════════════

/// A JSON-RPC 2.0 response frame. Exactly one of `result` / `error` is set
/// for a true response; a frame with `method` set is a server-initiated
/// request or notification instead.
public struct MCPRPCResponse: Codable, Sendable {
    public let jsonrpc: String?
    public let id: MCPRequestID?
    public let result: JSONRPCValue?
    public let error: MCPRPCError?
    /// Present only on server→client requests / notifications.
    public let method: String?
    public let params: JSONRPCValue?

    /// True when this frame is a response to one of our requests
    /// (carries an id and either result or error).
    public var isResponse: Bool { id != nil && method == nil }

    /// True when this frame is a server-initiated notification (method, no id).
    public var isNotification: Bool { method != nil && id == nil }

    /// True when this frame is a server-initiated request (method + id).
    public var isServerRequest: Bool { method != nil && id != nil }
}

/// A JSON-RPC 2.0 error object.
public struct MCPRPCError: Codable, Sendable, Error {
    public let code: Int
    public let message: String
    public let data: JSONRPCValue?

    public init(code: Int, message: String, data: JSONRPCValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    // Standard JSON-RPC error codes.
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - JSON value (params / result payloads)
// ═══════════════════════════════════════════════════════════════════

/// A self-contained JSON value used for JSON-RPC `params` and `result`.
/// Kept local to SwooshMCP so the module stays a leaf with no coupling to
/// SwooshTools' `JSONValue` (they are structurally identical).
public enum JSONRPCValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONRPCValue])
    case object([String: JSONRPCValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let i = try? c.decode(Int.self) { self = .int(i) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONRPCValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONRPCValue].self) { self = .object(o) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unrecognized JSON value") }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    // ── Accessors ─────────────────────────────────────────────────

    public var objectValue: [String: JSONRPCValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    public var arrayValue: [JSONRPCValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var intValue: Int? {
        if case .int(let i) = self { return i }
        return nil
    }

    public subscript(_ key: String) -> JSONRPCValue? {
        objectValue?[key]
    }

    /// Re-encodes this value to a compact JSON string (for storing schemas).
    public func jsonString() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
