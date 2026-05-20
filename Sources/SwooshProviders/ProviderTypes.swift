// SwooshProviders/ProviderTypes.swift — 0.9P Core Provider Contracts
//
// Model provider protocols. Streaming. Tool calls. Embeddings.
// Router. Health. Usage.
//
// Reuses ProviderID, ChatRole, ChatMessage, ToolCall, JSONValue from SwooshTools.

import Foundation
import SwooshTools
import SwooshSecrets
import CryptoKit

// ═══════════════════════════════════════════════════════════════════
// MARK: - SwooshTools ProviderID extensions
// ═══════════════════════════════════════════════════════════════════

extension ProviderID: CustomStringConvertible, ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self.init(rawValue: value) }
    public init(_ value: String) { self.init(rawValue: value) }
    public var description: String { rawValue }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Provider kind
// ═══════════════════════════════════════════════════════════════════

public enum ProviderKind: String, Codable, Sendable {
    case openAI, openRouter, elizaCloud
    case localOpenAICompatible, mlx, codexCLI
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Capabilities
// ═══════════════════════════════════════════════════════════════════

public struct ProviderCapabilities: Codable, Sendable {
    public let streaming: Bool
    public let toolCalling: Bool
    public let structuredOutput: Bool
    public let embeddings: Bool
    public let vision: Bool

    public init(streaming: Bool = false, toolCalling: Bool = false,
                structuredOutput: Bool = false, embeddings: Bool = false,
                vision: Bool = false) {
        self.streaming = streaming; self.toolCalling = toolCalling
        self.structuredOutput = structuredOutput; self.embeddings = embeddings
        self.vision = vision
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Model provider protocol
// ═══════════════════════════════════════════════════════════════════

public protocol ModelProviding: Sendable {
    var providerID: ProviderID { get }
    var displayName: String { get }
    var capabilities: ProviderCapabilities { get }

    func complete(_ request: ModelRequest) async throws -> ModelResponse
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Streaming provider
// ═══════════════════════════════════════════════════════════════════

public protocol StreamingModelProviding: ModelProviding {
    func stream(_ request: ModelRequest) async throws -> AsyncThrowingStream<ModelStreamEvent, Error>
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Tool-calling provider
// ═══════════════════════════════════════════════════════════════════

public protocol ToolCallingModelProviding: StreamingModelProviding {
    func completeWithTools(
        _ request: ModelRequest, tools: [ToolDescriptor]
    ) async throws -> ModelResponse
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Embedding provider
// ═══════════════════════════════════════════════════════════════════

public protocol EmbeddingProviding: Sendable {
    var providerID: ProviderID { get }
    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResponse
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Request / Response
// ═══════════════════════════════════════════════════════════════════

/// Provider-level model request. Uses SwooshTools.ChatMessage.
public struct ModelRequest: Sendable {
    public var model: String
    public var messages: [ChatMessage]
    public var instructions: String?
    public var tools: [ToolDescriptor]
    public var temperature: Double?
    public var maxOutputTokens: Int?
    public var stream: Bool
    public var metadata: [String: String]

    public init(model: String, messages: [ChatMessage], instructions: String? = nil,
                tools: [ToolDescriptor] = [], temperature: Double? = nil,
                maxOutputTokens: Int? = nil, stream: Bool = false,
                metadata: [String: String] = [:]) {
        self.model = model; self.messages = messages; self.instructions = instructions
        self.tools = tools; self.temperature = temperature
        self.maxOutputTokens = maxOutputTokens; self.stream = stream
        self.metadata = metadata
    }

    public func withModel(_ m: String) -> ModelRequest {
        var copy = self; copy.model = m; return copy
    }
}

/// Tool descriptor for provider tool calls (provider-facing, not SwooshTools.ToolDefinition).
public struct ToolDescriptor: Codable, Sendable {
    public let name: String
    public let description: String
    public let inputSchema: JSONValue

    public init(name: String, description: String, inputSchema: JSONValue) {
        self.name = name; self.description = description; self.inputSchema = inputSchema
    }
}

public struct ModelResponse: Sendable {
    public let providerID: ProviderID
    public let model: String
    public let text: String
    public let toolCalls: [ProviderToolCall]
    public let finishReason: String?
    public let usage: ProviderUsage?

    public init(providerID: ProviderID, model: String, text: String,
                toolCalls: [ProviderToolCall] = [], finishReason: String? = nil,
                usage: ProviderUsage? = nil) {
        self.providerID = providerID; self.model = model; self.text = text
        self.toolCalls = toolCalls; self.finishReason = finishReason; self.usage = usage
    }
}

public struct ProviderToolCall: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let arguments: JSONValue

    public init(id: String, name: String, arguments: JSONValue) {
        self.id = id; self.name = name; self.arguments = arguments
    }
}

public struct ProviderUsage: Codable, Sendable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int

    public init(promptTokens: Int, completionTokens: Int, totalTokens: Int) {
        self.promptTokens = promptTokens; self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Streaming events
// ═══════════════════════════════════════════════════════════════════

public enum ModelStreamEvent: Sendable {
    case textDelta(String)
    case toolCallDelta(ProviderToolCall)
    case usage(ProviderUsage)
    case done(ModelResponse)
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Embeddings
// ═══════════════════════════════════════════════════════════════════

public struct EmbeddingRequest: Codable, Sendable {
    public let model: String
    public let input: [String]

    public init(model: String, input: [String]) {
        self.model = model; self.input = input
    }
}

public struct EmbeddingResponse: Codable, Sendable {
    public let providerID: ProviderID
    public let model: String
    public let embeddings: [[Double]]
    public let usage: ProviderUsage?

    public init(providerID: ProviderID, model: String, embeddings: [[Double]],
                usage: ProviderUsage? = nil) {
        self.providerID = providerID; self.model = model
        self.embeddings = embeddings; self.usage = usage
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Provider auth
// ═══════════════════════════════════════════════════════════════════

public enum ProviderAuthKind: Codable, Sendable {
    case none
    case apiKey(namespace: String, key: String) // SecretRef components
    case pkce(providerID: String)
    case local
    case externalCLI(command: String)
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Provider profile
// ═══════════════════════════════════════════════════════════════════

public struct ProviderProfile: Codable, Sendable, Identifiable {
    public let id: ProviderID
    public var kind: ProviderKind
    public var displayName: String
    public var baseURL: String?
    public var auth: ProviderAuthKind
    public var defaultModel: String?
    public var enabled: Bool
    public var priority: Int

    public init(id: ProviderID, kind: ProviderKind, displayName: String,
                baseURL: String? = nil, auth: ProviderAuthKind = .none,
                defaultModel: String? = nil, enabled: Bool = false, priority: Int = 50) {
        self.id = id; self.kind = kind; self.displayName = displayName
        self.baseURL = baseURL; self.auth = auth; self.defaultModel = defaultModel
        self.enabled = enabled; self.priority = priority
    }

    public static let openAI = ProviderProfile(
        id: ProviderID("openai"), kind: .openAI, displayName: "OpenAI API",
        baseURL: "https://api.openai.com", auth: .apiKey(namespace: "openai", key: "api_key"),
        defaultModel: "gpt-4.1", enabled: false, priority: 100
    )

    public static let openRouter = ProviderProfile(
        id: ProviderID("openrouter"), kind: .openRouter, displayName: "OpenRouter",
        baseURL: "https://openrouter.ai/api/v1", auth: .apiKey(namespace: "openrouter", key: "api_key"),
        defaultModel: "openai/gpt-4.1", enabled: false, priority: 90
    )

    public static let elizaCloud = ProviderProfile(
        id: ProviderID("eliza-cloud"), kind: .elizaCloud, displayName: "Eliza Cloud",
        baseURL: "https://elizacloud.ai/api/v1", auth: .apiKey(namespace: "eliza-cloud", key: "api_key"),
        enabled: false, priority: 70
    )

    public static let localOpenAI = ProviderProfile(
        id: ProviderID("local-openai"), kind: .localOpenAICompatible, displayName: "Local OpenAI-Compatible",
        baseURL: "http://127.0.0.1:11434/v1", auth: .none,
        enabled: false, priority: 60
    )

    public static let mlxLocal = ProviderProfile(
        id: ProviderID("mlx-local"), kind: .mlx, displayName: "MLX Local",
        auth: .local, enabled: false, priority: 80
    )
}

// ═══════════════════════════════════════════════════════════════════
