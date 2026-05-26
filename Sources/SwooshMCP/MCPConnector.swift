// SwooshMCP/MCPConnector.swift — 0.8C MCP connect → discover → register
//
// Closes the loop from an MCPServerProfile to discovered tools landing in
// MCPServerRegistry. This is the layer that turns "server config" into
// "tools the registry knows about".
//
// Safety contract preserved:
//   • Stdio and HTTP profiles connect here.
//   • The registry's existing gates still apply: a server must be enabled
//     before registerDiscoveredTools accepts its tools.
//   • Imported tools stay UNTRUSTED — registry policy and trust level are
//     unchanged by discovery. Nothing here registers into the main
//     ToolRegistry or grants any permission; that wiring is a follow-up.
//   • This layer performs transport + discovery only. It does not call
//     tools, write memory, or touch audit beyond the registry's own log.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Connector errors
// ═══════════════════════════════════════════════════════════════════

public enum MCPConnectorError: Error, Sendable {
    case unsupportedTransport(String)
    case serverNotFound(String)
    case serverDisabled(String)
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Discovery outcome
// ═══════════════════════════════════════════════════════════════════

public struct MCPDiscoveryResult: Sendable {
    public let serverID: String
    public let handshake: MCPServerHandshake
    public let toolCount: Int
    public let toolNames: [String]

    public init(serverID: String, handshake: MCPServerHandshake,
                toolCount: Int, toolNames: [String]) {
        self.serverID = serverID
        self.handshake = handshake
        self.toolCount = toolCount
        self.toolNames = toolNames
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Connector
// ═══════════════════════════════════════════════════════════════════

public struct MCPConnector: Sendable {

    /// Resolves a Keychain secret-ref to its raw value. Defaults to a
    /// no-op resolver so configs with `environmentSecretRefs` simply pass
    /// the ref through unresolved if no real resolver is supplied. The
    /// daemon injects a real Keychain-backed resolver.
    public typealias SecretResolver = @Sendable (String) async -> String?

    private let secretResolver: SecretResolver
    private let clientInfo: MCPClientInfo
    private let requestTimeout: TimeInterval
    private let httpSender: HTTPMCPTransport.Configuration.Sender?

    public init(clientInfo: MCPClientInfo = .swoosh,
                requestTimeout: TimeInterval = 30,
                secretResolver: @escaping SecretResolver = { _ in nil }) {
        self.init(
            clientInfo: clientInfo,
            requestTimeout: requestTimeout,
            httpSender: nil,
            secretResolver: secretResolver
        )
    }

    public init(clientInfo: MCPClientInfo = .swoosh,
                requestTimeout: TimeInterval = 30,
                httpSender: HTTPMCPTransport.Configuration.Sender?,
                secretResolver: @escaping SecretResolver = { _ in nil }) {
        self.clientInfo = clientInfo
        self.requestTimeout = requestTimeout
        self.httpSender = httpSender
        self.secretResolver = secretResolver
    }

    // ── Build a client from a profile ─────────────────────────────

    #if os(macOS) || os(Linux)
    /// Builds (but does not connect) an MCPClient for a configured profile.
    public func makeClient(for profile: MCPServerProfile,
                           stderrSink: @escaping @Sendable (String) -> Void = { _ in }) async throws -> MCPClient {
        switch profile.transport {
        case .stdio(let cfg):
            // Resolve env secret refs → raw values for the child's environment.
            // Unresolved refs pass through as-is per the documented contract,
            // so the server gets *some* value rather than silently nothing.
            var env: [String: String] = [:]
            for (key, ref) in cfg.environmentSecretRefs {
                env[key] = await secretResolver(ref) ?? ref
            }
            let config = StdioMCPTransport.Configuration(
                executable: cfg.command,
                arguments: cfg.arguments,
                workingDirectory: cfg.workingDirectory,
                environment: env
            )
            let transport = StdioMCPTransport(config: config, stderrSink: stderrSink)
            return MCPClient(transport: transport, clientInfo: clientInfo, requestTimeout: requestTimeout)
        case .http(let cfg):
            guard let endpoint = URL(string: cfg.baseURL) else {
                throw MCPConnectorError.unsupportedTransport("invalid http MCP baseURL")
            }
            guard !cfg.localOnly || Self.isLocalEndpoint(endpoint) else {
                throw MCPConnectorError.unsupportedTransport("http MCP server is not local; set localOnly=false for hosted MCP")
            }
            var headers: [String: String] = [:]
            if let ref = cfg.authorizationSecretRef,
               let raw = await secretResolver(ref)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !raw.isEmpty {
                headers["Authorization"] = raw.localizedCaseInsensitiveContains("bearer ") ? raw : "Bearer \(raw)"
                headers["x-api-key"] = raw
            }
            let transport = HTTPMCPTransport(config: .init(endpoint: endpoint, headers: headers, sender: httpSender))
            return MCPClient(transport: transport, clientInfo: clientInfo, requestTimeout: requestTimeout)
        }
    }
    #endif

    private static func isLocalEndpoint(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "localhost" || host.hasSuffix(".local") { return true }
        if host == "127.0.0.1" || host == "::1" { return true }
        if host.hasPrefix("10.") || host.hasPrefix("192.168.") { return true }
        let private172 = (16...31).map { "172.\($0)." }
        return private172.contains { host.hasPrefix($0) }
    }

    // ── Connect + discover + register ─────────────────────────────

    /// Connects a configured MCP server, runs the `initialize` handshake,
    /// fetches its tools via `tools/list`, and registers them into
    /// `registry`. Returns a summary. The client is disconnected before
    /// returning — discovery is a one-shot pass.
    ///
    /// The server must already be present in the registry and `enabled`
    /// (the registry's `registerDiscoveredTools` enforces this).
    #if os(macOS) || os(Linux)
    @discardableResult
    public func connectAndDiscover(serverID: String,
                                   registry: MCPServerRegistry) async throws -> MCPDiscoveryResult {
        guard let profile = await registry.getServer(serverID) else {
            throw MCPConnectorError.serverNotFound(serverID)
        }
        guard profile.enabled else {
            throw MCPConnectorError.serverDisabled(serverID)
        }

        let client = try await makeClient(for: profile)
        do {
            try await client.connect()
            let handshake = try await client.initialize()
            let listed = try await client.listTools()
            await client.disconnect()

            // Map MCP tools → registry descriptors.
            let descriptors = listed.map { tool in
                MCPToolDescriptor(
                    serverID: serverID,
                    name: tool.name,
                    title: tool.title,
                    description: tool.description,
                    inputSchemaJSON: tool.inputSchemaJSON
                )
            }
            try await registry.registerDiscoveredTools(serverID, tools: descriptors)
            return MCPDiscoveryResult(
                serverID: serverID,
                handshake: handshake,
                toolCount: descriptors.count,
                toolNames: descriptors.map { $0.name }
            )
        } catch {
            await client.disconnect()
            throw error
        }
    }
    #endif

    /// Discovers tools from an already-connected, already-initialized client
    /// and registers them. Useful when a long-lived connection is held
    /// elsewhere (and exercisable in tests with a mock transport).
    @discardableResult
    public func discoverAndRegister(serverID: String,
                                    client: MCPClient,
                                    registry: MCPServerRegistry) async throws -> MCPDiscoveryResult {
        guard let profile = await registry.getServer(serverID) else {
            throw MCPConnectorError.serverNotFound(serverID)
        }
        let listed = try await client.listTools()
        let descriptors = listed.map { tool in
            MCPToolDescriptor(
                serverID: serverID,
                name: tool.name,
                title: tool.title,
                description: tool.description,
                inputSchemaJSON: tool.inputSchemaJSON
            )
        }
        try await registry.registerDiscoveredTools(serverID, tools: descriptors)
        // Synthesize a handshake summary from what we know.
        let handshake = MCPServerHandshake(
            protocolVersion: MCPProtocol.revision,
            serverName: profile.name,
            serverVersion: "unknown",
            hasToolsCapability: true,
            hasResourcesCapability: false,
            hasPromptsCapability: false
        )
        return MCPDiscoveryResult(
            serverID: serverID,
            handshake: handshake,
            toolCount: descriptors.count,
            toolNames: descriptors.map { $0.name }
        )
    }
}
