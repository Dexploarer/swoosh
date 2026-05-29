// SwooshTools/Tool.swift — The Typed Tool Contract (0.4A)
//
// Every tool in Swoosh is a Swift type. Typed at compile time.
// Permissioned. Replayable. Auditable.
//
// 0.4A rule: Every tool is typed. Every risky action is permissioned.
// Every sensitive action is auditable.

import Foundation

// MARK: - Tool name

public struct ToolName: Hashable, Codable, Sendable, RawRepresentable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ value: String) { self.rawValue = value }
    public init(stringLiteral value: String) { self.rawValue = value }
}

// MARK: - Toolset ID

public enum ToolsetID: String, Codable, Sendable, CaseIterable {
    case core
    case memory
    case permissions
    case scout
    case audit
    case files
    case git
    case swiftDev
    case xcode
    case web
    case browser
    case terminal
    case apple
    case workflow
    case cron
    case evm
    case solana
    case launchpads
    case hyperliquid
    case uniswap
    case mcp
    case skills
    case goals
    case manifesting
    case plugins
    case mediaGen
    case nitrogen
    case calendar

    /// Toolsets whose successful calls generate on-chain receipt
    /// anchoring entries (for optional rebate earning).
    public var isCrypto: Bool {
        switch self {
        case .evm, .solana, .launchpads, .hyperliquid, .uniswap: return true
        default: return false
        }
    }
}

// MARK: - SwooshTool protocol (typed)

/// A typed, permissioned, replayable tool that an agent can invoke.
/// Every tool has a typed Input/Output, permission, risk, and approval policy.
public protocol SwooshTool: Sendable {
    associatedtype Input: Codable & Sendable
    associatedtype Output: Codable & Sendable

    static var name: ToolName { get }
    static var displayName: String { get }
    static var description: String { get }
    static var permission: SwooshPermission { get }
    static var risk: ToolRisk { get }
    static var approval: ApprovalPolicy { get }
    static var toolset: ToolsetID { get }

    /// Platforms on which this tool may be registered. Defaults to the
    /// owning toolset's `defaultPlatforms`. Override only when a single
    /// tool diverges from its toolset (e.g., a memory tool that needs
    /// Platform availability.
    static var platforms: Set<ToolPlatform> { get }
    /// Whether this tool requires $DTOUR stake to execute.
    /// Default: false. Only set to true for premium actions
    /// like launching tokens on launchpad platforms.
    static var isTokenGated: Bool { get }

    func call(
        _ input: Input,
        context: ToolContext
    ) async throws -> Output
}

extension SwooshTool {
    public static var platforms: Set<ToolPlatform> { Self.toolset.defaultPlatforms }
    public static var isTokenGated: Bool { false }
}

// MARK: - Type-erased wrapper

/// Type-erased wrapper for tools so the registry can hold heterogeneous tools.
public protocol AnySwooshTool: Sendable {
    var descriptor: ToolDescriptor { get }

    func callJSON(
        _ input: JSONValue,
        context: ToolContext
    ) async throws -> JSONValue
}

// MARK: - Concrete type erasure

/// Wraps any SwooshTool into an AnySwooshTool for registry storage.
public struct TypeErasedTool<T: SwooshTool>: AnySwooshTool {
    private let tool: T

    public init(_ tool: T) { self.tool = tool }

    public var descriptor: ToolDescriptor {
        ToolDescriptor(
            id: T.name.rawValue,
            name: T.name.rawValue,
            displayName: T.displayName,
            description: T.description,
            inputSchema: JSONSchema(type: "object", description: "Input for \(T.name.rawValue)"),
            outputSchema: JSONSchema(type: "object", description: "Output for \(T.name.rawValue)"),
            permission: T.permission,
            risk: T.risk,
            approval: T.approval,
            toolset: T.toolset,
            platforms: T.platforms,
            isTokenGated: T.isTokenGated
        )
    }

    public func callJSON(
        _ input: JSONValue,
        context: ToolContext
    ) async throws -> JSONValue {
        let data = try JSONEncoder().encode(input)
        let typedInput = try JSONDecoder().decode(T.Input.self, from: data)
        let output = try await tool.call(typedInput, context: context)
        let outputData = try JSONEncoder().encode(output)
        return try JSONDecoder().decode(JSONValue.self, from: outputData)
    }
}

// MARK: - Tool descriptor

public struct ToolDescriptor: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let displayName: String
    public let description: String
    public let inputSchema: JSONSchema
    public let outputSchema: JSONSchema
    public let permission: SwooshPermission
    public let risk: ToolRisk
    public let approval: ApprovalPolicy
    public let toolset: ToolsetID
    public let platforms: Set<ToolPlatform>
    /// True only for premium actions (e.g. launching tokens on
    /// launchpad platforms). Requires $DTOUR stake to execute.
    public let isTokenGated: Bool

    public init(
        id: String,
        name: String,
        displayName: String,
        description: String,
        inputSchema: JSONSchema,
        outputSchema: JSONSchema,
        permission: SwooshPermission,
        risk: ToolRisk,
        approval: ApprovalPolicy,
        toolset: ToolsetID,
        platforms: Set<ToolPlatform> = [.macOS, .iOS, .linux],
        isTokenGated: Bool = false
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.description = description
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.permission = permission
        self.risk = risk
        self.approval = approval
        self.toolset = toolset
        self.platforms = platforms
        self.isTokenGated = isTokenGated
    }

    // Backward-compat decoding: descriptors persisted before the
    // `platforms` field existed should still load, defaulting to "runs
    // anywhere".
    private enum CodingKeys: String, CodingKey {
        case id, name, displayName, description, inputSchema, outputSchema
        case permission, risk, approval, toolset, platforms, isTokenGated
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.displayName = try c.decode(String.self, forKey: .displayName)
        self.description = try c.decode(String.self, forKey: .description)
        self.inputSchema = try c.decode(JSONSchema.self, forKey: .inputSchema)
        self.outputSchema = try c.decode(JSONSchema.self, forKey: .outputSchema)
        self.permission = try c.decode(SwooshPermission.self, forKey: .permission)
        self.risk = try c.decode(ToolRisk.self, forKey: .risk)
        self.approval = try c.decode(ApprovalPolicy.self, forKey: .approval)
        self.toolset = try c.decode(ToolsetID.self, forKey: .toolset)
        self.platforms = (try? c.decode(Set<ToolPlatform>.self, forKey: .platforms))
            ?? [.macOS, .iOS, .linux]
        self.isTokenGated = (try? c.decode(Bool.self, forKey: .isTokenGated)) ?? false
    }
}

// MARK: - Tool context

public struct ToolContext: Sendable {
    public let sessionID: String
    public let safetyConfig: SwooshSafetyConfig
    public let toolPolicy: ToolCallPolicy
    public let isModelInvocation: Bool
    public let callerIdentity: String
    /// Wallet address of the caller. Required for crypto toolsets
    /// (stake gating + receipt tracking). Empty for non-crypto calls.
    public let walletAddress: String

    public init(
        sessionID: String,
        safetyConfig: SwooshSafetyConfig = .defaultAgent,
        toolPolicy: ToolCallPolicy = .defaultAgent,
        isModelInvocation: Bool = true,
        callerIdentity: String = "agent",
        walletAddress: String = ""
    ) {
        self.sessionID = sessionID
        self.safetyConfig = safetyConfig
        self.toolPolicy = toolPolicy
        self.isModelInvocation = isModelInvocation
        self.callerIdentity = callerIdentity
        self.walletAddress = walletAddress
    }

    public func withSafetyConfig(_ safetyConfig: SwooshSafetyConfig) -> ToolContext {
        ToolContext(
            sessionID: sessionID,
            safetyConfig: safetyConfig,
            toolPolicy: toolPolicy,
            isModelInvocation: isModelInvocation,
            callerIdentity: callerIdentity,
            walletAddress: walletAddress
        )
    }
}

// MARK: - Firewall protocol

/// Permission enforcement boundary. No tool bypasses this.
public protocol Firewall: Sendable {
    func require(_ permission: SwooshPermission) async throws
    func isGranted(_ permission: SwooshPermission) async -> Bool
}

/// Persists firewall permission grants across process restarts.
/// Injected into the firewall at init; the firewall loads on boot and
/// writes through on every grant/deny/revoke.
public protocol PermissionPersisting: Sendable {
    func loadGrants() async throws -> [(permission: SwooshPermission, granted: Bool)]
    func saveGrant(_ permission: SwooshPermission, granted: Bool) async throws
    func removeGrant(_ permission: SwooshPermission) async throws
}

// MARK: - Stake gating protocol

/// Stake-to-act gating — checked before crypto tool execution.
/// Throws `ToolError.denied` if the wallet has insufficient stake.
public protocol StakeGating: Sendable {
    func requireStake(wallet: String, toolsetID: String) async throws
}

// MARK: - Receipt tracking protocol

/// Receipt tracking — called after crypto tool success for rebate
/// accounting and on-chain anchoring eligibility.
public protocol ReceiptTracking: Sendable {
    func trackReceipt(
        auditEntryID: String, toolName: String,
        toolsetID: String, wallet: String
    ) async throws
}

// MARK: - Audit logging protocol

public protocol AuditLogging: Sendable {
    func append(_ event: AuditEntry) async throws
    func tail(limit: Int) async -> [AuditEntry]
    func search(query: String, limit: Int) async -> [AuditEntry]
    func getEvent(id: String) async -> AuditEntry?
}

public struct AuditEntry: Codable, Sendable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let kind: AuditEntryKind
    public let toolName: String?
    public let sessionID: String?
    public let detail: String
    public let success: Bool

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        kind: AuditEntryKind,
        toolName: String? = nil,
        sessionID: String? = nil,
        detail: String,
        success: Bool = true
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.toolName = toolName
        self.sessionID = sessionID
        self.detail = detail
        self.success = success
    }
}

public enum AuditEntryKind: String, Codable, Sendable {
    case toolCallStarted
    case toolCallSucceeded
    case toolCallFailed
    case toolCallDenied
    case memoryProposed
    case memoryApproved
    case memoryRejected
    case memoryEdited
    case permissionGranted
    case permissionDenied
    case approvalGranted
    case approvalDenied
    case workflowStarted
    case workflowCompleted
    case safetyViolation
    /// `SwooshNetworkPolicy` allowed an outbound HTTP request. `detail`
    /// carries the scheme, host, and purpose label so reviewers can see
    /// what was reached. Distinct from `toolCallStarted` (which is the
    /// tool registry's own event) — auditors that want to filter for
    /// network egress shouldn't have to wade through tool calls.
    case egressAllowed
    /// `SwooshNetworkPolicy` denied an outbound HTTP request. `detail`
    /// carries the reason the gate returned plus the scheme/host/purpose.
    case egressDenied
    /// Plugin lifecycle or per-tool-call event from `SwooshPlugins`.
    /// The `detail` field carries the specific `PluginAuditEventKind` and the
    /// plugin ID. `success` is false for sandbox violations / failed tool
    /// calls. Plugin tool calls *also* generate ordinary `toolCallStarted` /
    /// `toolCallSucceeded` entries through the registry — this kind covers
    /// the lifecycle events the registry doesn't see (discovery, enable,
    /// disable, sandbox refusals).
    case pluginEvent
}

// MARK: - JSONValue extensions

extension JSONValue {
    /// Returns a redacted preview suitable for audit logs.
    /// Truncates long strings, replaces known sensitive patterns.
    public func redactedPreview(maxLength: Int = 200) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(self),
              var text = String(data: data, encoding: .utf8) else {
            return "<unserializable>"
        }
        // Redact known sensitive patterns
        let sensitivePatterns = [
            "private_key", "privateKey", "seed_phrase", "seedPhrase",
            "mnemonic", "password", "secret", "cookie", "token"
        ]
        for pattern in sensitivePatterns {
            if text.localizedCaseInsensitiveContains(pattern) {
                let regexPattern = "\"\(pattern)\"\\s*:\\s*\"[^\"]*\""
                if let regex = try? NSRegularExpression(pattern: regexPattern, options: .caseInsensitive) {
                    text = regex.stringByReplacingMatches(
                        in: text,
                        range: NSRange(text.startIndex..., in: text),
                        withTemplate: "\"\(pattern)\":\"[REDACTED]\""
                    )
                }
            }
        }
        if text.count > maxLength {
            return String(text.prefix(maxLength)) + "…"
        }
        return text
    }
}
