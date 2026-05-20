// SwooshBridge/Bridge.swift — Python / Node / MCP interop
//
// Swift owns orchestration. External workers handle the ecosystem.

import Foundation
import SwooshTools

// MARK: - Worker protocol

/// A foreign-language worker that Swoosh orchestrates.
/// Swift controls security, transport, approval, and file boundaries.
public protocol ForeignWorker: Sendable {
    var language: WorkerLanguage { get }

    func execute(
        source: String,
        context: WorkerContext
    ) async throws -> WorkerResult
}

public enum WorkerLanguage: String, Codable, Sendable {
    case python
    case node
    case shell
    case swift
}

public struct WorkerContext: Sendable {
    public let workingDirectory: URL
    public let environment: [String: String]
    public let timeout: TimeInterval

    public init(
        workingDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        environment: [String: String] = [:],
        timeout: TimeInterval = 60
    ) {
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.timeout = timeout
    }
}

public struct WorkerResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public init(stdout: String, stderr: String = "", exitCode: Int32 = 0) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }

    public var succeeded: Bool { exitCode == 0 }
}

public enum MCPBridgeError: Error, Sendable, LocalizedError {
    case transportUnavailable(String)
    case serverNotImported(String)

    public var errorDescription: String? {
        switch self {
        case .transportUnavailable(let operation):
            return "MCP bridge transport is unavailable for \(operation)"
        case .serverNotImported(let name):
            return "MCP server is not imported: \(name)"
        }
    }
}

// MARK: - MCP bridge

/// Import MCP servers, export Swift tools as MCP, generate typed wrappers.
public actor MCPBridge {
    public struct ImportedServer: Sendable {
        public let name: String
        public let command: String
        public let arguments: [String]
        public let tools: [MCPImportedTool]
    }

    public struct MCPImportedTool: Sendable {
        public let name: String
        public let description: String
        public let inputSchema: JSONSchema
    }

    private var servers: [String: ImportedServer] = [:]

    public init() {}

    /// Import an MCP server and discover its tools.
    public func importServer(name: String, command: String, arguments: [String] = []) async throws {
        throw MCPBridgeError.transportUnavailable("importServer(\(name), command: \(command), arguments: \(arguments.count))")
    }

    /// List all imported MCP tools with swoosh-prefixed names.
    public func allTools() -> [(server: String, tool: MCPImportedTool)] {
        servers.flatMap { serverName, server in
            server.tools.map { (server: serverName, tool: $0) }
        }
    }

    /// Export a set of Swoosh tools as an MCP server.
    public func exportAsServer(tools: [any AnySwooshTool], port: Int) async throws {
        throw MCPBridgeError.transportUnavailable("exportAsServer(tools: \(tools.count), port: \(port))")
    }

    /// Generate a typed Swift wrapper for an imported MCP server's tools.
    public func generateSwiftWrapper(for serverName: String) throws -> String {
        guard let server = servers[serverName] else { throw MCPBridgeError.serverNotImported(serverName) }

        var code = "// Auto-generated Swift wrapper for MCP server: \(serverName)\n\n"
        code += "import SwooshTools\n\n"
        code += "public enum \(serverName.capitalized)MCP {\n"

        for tool in server.tools {
            let funcName = tool.name.replacingOccurrences(of: ".", with: "_")
            code += "    public static func \(funcName)(_ arguments: JSONValue) async throws -> JSONValue {\n"
            code += "        throw ToolError.executionFailed(\"MCP bridge wrapper \(serverName).\(tool.name) is not bound to an MCP transport\")\n"
            code += "    }\n\n"
        }

        code += "}\n"
        return code
    }
}
