// SwooshLSP/LSPClient.swift — Language Server Protocol client
//
// JSON-RPC connection to language servers (SourceKit-LSP, etc.)
// for code intelligence: diagnostics, completions, hover, go-to-definition.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - LSP message types
// ═══════════════════════════════════════════════════════════════════

public struct LSPRequest: Codable, Sendable {
    public let jsonrpc: String = "2.0"
    public let id: Int
    public let method: String
    public let params: [String: LSPValue]?
    public init(id: Int, method: String, params: [String: LSPValue]? = nil) {
        self.id = id; self.method = method; self.params = params
    }
}

public struct LSPNotification: Codable, Sendable {
    public let jsonrpc: String = "2.0"
    public let method: String
    public let params: [String: LSPValue]?
    public init(method: String, params: [String: LSPValue]? = nil) {
        self.method = method; self.params = params
    }
}

public enum LSPValue: Codable, Sendable {
    case string(String), int(Int), bool(Bool), null
    case array([LSPValue]), object([String: LSPValue])
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if c.decodeNil() { self = .null }
        else if let v = try? c.decode([LSPValue].self) { self = .array(v) }
        else if let v = try? c.decode([String: LSPValue].self) { self = .object(v) }
        else { self = .null }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
    public var stringValue: String? { if case .string(let v) = self { return v }; return nil }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - LSP diagnostic types
// ═══════════════════════════════════════════════════════════════════

public struct LSPDiagnostic: Codable, Sendable {
    public let range: LSPRange
    public let severity: Int?
    public let message: String
    public let source: String?
    public init(range: LSPRange, severity: Int? = nil, message: String, source: String? = nil) {
        self.range = range; self.severity = severity; self.message = message; self.source = source
    }
    public var severityLabel: String {
        switch severity {
        case 1: return "error"; case 2: return "warning"; case 3: return "info"; case 4: return "hint"
        default: return "unknown"
        }
    }
}

public struct LSPRange: Codable, Sendable {
    public let start: LSPPosition; public let end: LSPPosition
    public init(start: LSPPosition, end: LSPPosition) { self.start = start; self.end = end }
}

public struct LSPPosition: Codable, Sendable {
    public let line: Int; public let character: Int
    public init(line: Int, character: Int) { self.line = line; self.character = character }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - LSP client
// ═══════════════════════════════════════════════════════════════════

/// JSON-RPC client for Language Server Protocol.
public actor LSPClient {
    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var nextID: Int = 1
    private var isInitialized = false
    private let serverPath: String

    public init(serverPath: String = "/usr/bin/sourcekit-lsp") {
        self.serverPath = serverPath
    }

    /// Start the LSP server process.
    public func start(rootURI: String) async throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: serverPath)
        let stdinPipe = Pipe(); let stdoutPipe = Pipe()
        proc.standardInput = stdinPipe; proc.standardOutput = stdoutPipe; proc.standardError = FileHandle.nullDevice
        try proc.run()
        process = proc; stdin = stdinPipe.fileHandleForWriting; stdout = stdoutPipe.fileHandleForReading

        // Initialize
        let id = nextID; nextID += 1
        let initParams: [String: LSPValue] = [
            "processId": .int(Int(ProcessInfo.processInfo.processIdentifier)),
            "rootUri": .string(rootURI),
            "capabilities": .object([:])
        ]
        try sendRequest(id: id, method: "initialize", params: initParams)
        try sendNotification(method: "initialized", params: [:])
        isInitialized = true
    }

    /// Stop the LSP server.
    public func stop() async throws {
        if isInitialized { try sendRequest(id: nextID, method: "shutdown", params: nil) }
        process?.terminate(); process = nil; isInitialized = false
    }

    /// Get diagnostics for a file by opening it.
    public func openFile(uri: String, text: String, language: String = "swift") throws {
        try sendNotification(method: "textDocument/didOpen", params: [
            "textDocument": .object([
                "uri": .string(uri), "languageId": .string(language),
                "version": .int(1), "text": .string(text)
            ])
        ])
    }

    /// Check if sourcekit-lsp is available.
    public static func isAvailable() -> Bool {
        FileManager.default.fileExists(atPath: "/usr/bin/sourcekit-lsp")
    }

    // ── Internal ──

    private func sendRequest(id: Int, method: String, params: [String: LSPValue]?) throws {
        let req = LSPRequest(id: id, method: method, params: params)
        let data = try JSONEncoder().encode(req)
        let header = "Content-Length: \(data.count)\r\n\r\n"
        guard let headerData = header.data(using: .utf8) else { return }
        stdin?.write(headerData); stdin?.write(data)
    }

    private func sendNotification(method: String, params: [String: LSPValue]?) throws {
        let note = LSPNotification(method: method, params: params)
        let data = try JSONEncoder().encode(note)
        let header = "Content-Length: \(data.count)\r\n\r\n"
        guard let headerData = header.data(using: .utf8) else { return }
        stdin?.write(headerData); stdin?.write(data)
    }
}
