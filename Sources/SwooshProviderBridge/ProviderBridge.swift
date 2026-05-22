// SwooshProviderBridge/ProviderBridge.swift — Bridge SwooshProviders → SwooshCore
//
// Adapts the real ProviderRouter to the SwooshCore ModelProvider protocol.
// Handles type conversion between SwooshCore.ChatMessage and SwooshTools.ChatMessage.
//
// Originally lived in SwooshCLI; promoted to its own library so the daemon
// can mount the real inference stack instead of LocalDiagnosticProvider.

import Foundation
import SwooshCore
import SwooshMLX
import SwooshModels
import SwooshProviders
import SwooshSecrets
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Provider Bridge Adapter
// ═══════════════════════════════════════════════════════════════════

/// Bridges the real `ProviderRouter` to `SwooshCore.ModelProvider`.
/// This is the integration point where Swoosh starts using real LLM inference.
public final class ProviderBridgeAdapter: SwooshCore.ModelProvider, @unchecked Sendable {
    public let providerID: String = "provider-router"
    public let modelName: String

    private let router: ProviderRouter
    private let role: SwooshProviders.ModelRole
    private let defaultProviderID: String?

    public init(
        router: ProviderRouter,
        role: SwooshProviders.ModelRole = .primaryChat,
        modelName: String = "auto",
        defaultProviderID: String? = nil
    ) {
        self.router = router
        self.role = role
        self.modelName = modelName
        self.defaultProviderID = defaultProviderID
    }

    public func complete(_ request: SwooshCore.ModelCompletionRequest) async throws -> SwooshCore.ModelCompletionResponse {
        // Convert SwooshCore messages → SwooshTools messages
        let toolsMessages: [SwooshTools.ChatMessage] = request.messages.map { msg in
            SwooshTools.ChatMessage(
                role: convertRole(msg.role),
                content: msg.content
            )
        }

        // Build provider request
        let routedProviderID = request.providerID ?? defaultProviderID
        let metadata = routedProviderID.map { ["providerID": $0] } ?? [:]
        let modelRequest = ModelRequest(
            model: request.model ?? modelName,
            messages: toolsMessages,
            tools: request.tools.map(Self.providerToolDescriptor),
            metadata: metadata
        )

        // Route through real providers
        let response = try await router.complete(role: role, request: modelRequest)

        // Convert response back
        let toolCalls: [SwooshCore.NativeToolCall] = response.toolCalls.map { tc in
            NativeToolCall(id: tc.id, name: tc.name, arguments: tc.arguments)
        }

        let usage = SwooshCore.ModelUsage(
            promptTokens: response.usage?.promptTokens ?? 0,
            completionTokens: response.usage?.completionTokens ?? 0,
            totalTokens: response.usage?.totalTokens ?? 0
        )

        return SwooshCore.ModelCompletionResponse(
            content: response.text,
            model: response.model,
            usage: usage,
            toolCalls: toolCalls,
            isToolCallMode: !toolCalls.isEmpty
        )
    }

    // ── Type conversions ──────────────────────────────────────────

    private func convertRole(_ role: SwooshCore.ChatRole) -> SwooshTools.ChatRole {
        switch role {
        case .system: return .system
        case .user: return .user
        case .assistant: return .assistant
        case .tool: return .tool
        }
    }

    private static func providerToolDescriptor(
        _ descriptor: SwooshTools.ToolDescriptor
    ) -> SwooshProviders.ToolDescriptor {
        SwooshProviders.ToolDescriptor(
            name: descriptor.name,
            description: descriptor.description,
            inputSchema: descriptor.inputSchema.asJSONValue()
        )
    }
}

private extension SwooshTools.JSONSchema {
    func asJSONValue() -> SwooshTools.JSONValue {
        let encoder = JSONEncoder()
        guard
            let data = try? encoder.encode(self),
            let value = try? JSONDecoder().decode(SwooshTools.JSONValue.self, from: data)
        else {
            return .object(["type": .string("object")])
        }
        return value
    }
}

public actor MLXLocalProvider: SwooshProviders.ModelProviding {
    public nonisolated let providerID = ProviderID(ModelDefaults.localMLXProviderID)
    public nonisolated let displayName = "MLX Local"
    public nonisolated let capabilities = ProviderCapabilities(
        streaming: false,
        toolCalling: false,
        structuredOutput: true,
        embeddings: false,
        vision: true
    )

    private let engine: MLXInferenceEngine

    public init(engine: MLXInferenceEngine = MLXInferenceEngine()) {
        self.engine = engine
    }

    public func complete(_ request: SwooshProviders.ModelRequest) async throws -> SwooshProviders.ModelResponse {
        let model = Self.resolvedModel(request.model)
        if await engine.currentModel() != model {
            try await engine.loadModel(id: model)
        }
        let output = try await engine.generate(
            prompt: Self.flatten(request.messages),
            maxTokens: request.maxOutputTokens ?? 512,
            temperature: request.temperature ?? 0.7
        )
        return SwooshProviders.ModelResponse(
            providerID: providerID,
            model: model,
            text: output
        )
    }

    private static func resolvedModel(_ model: String) -> String {
        guard !model.isEmpty, model != "auto" else {
            return ModelDefaults.localMLXModelID
        }
        return model
    }

    private static func flatten(_ messages: [SwooshTools.ChatMessage]) -> String {
        var lines: [String] = []
        for message in messages {
            let tag: String
            switch message.role {
            case .system:    tag = "System"
            case .developer: tag = "Developer"
            case .user:      tag = "User"
            case .assistant: tag = "Assistant"
            case .tool:      tag = "Tool"
            }
            lines.append("[\(tag)]\n\(message.content)")
        }
        lines.append("[Assistant]\n")
        return lines.joined(separator: "\n\n")
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Provider Factory
// ═══════════════════════════════════════════════════════════════════

/// Builds the full provider stack from Keychain secrets.
/// Used by CLI commands to bootstrap the inference pipeline.
public struct ProviderFactory {

    public static func buildRouter(
        secrets: any SecretStoring,
        preferredProviderID: String? = nil
    ) async -> (ProviderRouter, ProviderRegistry) {
        let registry = ProviderRegistry()

        // Register all available providers
        let codex = CodexBridgeProvider()
        await registry.register(codex, profile: .codex)

        let openai = OpenAIResponsesProvider(secrets: secrets)
        await registry.register(openai, profile: .openAI)

        let openrouter = OpenRouterProvider(secrets: secrets)
        await registry.register(openrouter, profile: .openRouter)

        let eliza = ElizaCloudProvider(secrets: secrets)
        await registry.register(eliza, profile: .elizaCloud)

        let mlx = MLXLocalProvider()
        await registry.register(mlx, profile: .mlxLocal)

        let local = LocalOpenAICompatibleProvider()
        await registry.register(local, profile: .localOpenAI)
        let localRouteModel = await localModelRouteDefault()

        await addRoute(to: registry, role: .primaryChat, providerID: ModelDefaults.codexProviderID,
                       model: ModelDefaults.codexModelID, defaultPriority: 120, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .primaryChat, providerID: ModelDefaults.openAIProviderID,
                       model: ModelDefaults.openAIModelID, defaultPriority: 100, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .primaryChat, providerID: ModelDefaults.openRouterProviderID,
                       model: ModelDefaults.openRouterModelID, defaultPriority: 90, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .primaryChat, providerID: ModelDefaults.elizaCloudProviderID,
                       model: ModelDefaults.elizaCloudModelID, defaultPriority: 70, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .primaryChat, providerID: ModelDefaults.localMLXProviderID,
                       model: ModelDefaults.localMLXModelID, defaultPriority: 65, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .primaryChat, providerID: ModelDefaults.localOpenAIProviderID,
                       model: localRouteModel, defaultPriority: 60, preferredProviderID: preferredProviderID)

        await addRoute(to: registry, role: .coding, providerID: ModelDefaults.codexProviderID,
                       model: ModelDefaults.codexModelID, defaultPriority: 110, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .coding, providerID: ModelDefaults.openAIProviderID,
                       model: ModelDefaults.openAICodingModelID, defaultPriority: 100, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .coding, providerID: ModelDefaults.openRouterProviderID,
                       model: ModelDefaults.openRouterCodingModelID, defaultPriority: 90, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .coding, providerID: ModelDefaults.localOpenAIProviderID,
                       model: "qwen3-coder-next", defaultPriority: 70, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .coding, providerID: ModelDefaults.localOpenAIProviderID,
                       model: localRouteModel, defaultPriority: 55, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .coding, providerID: ModelDefaults.localMLXProviderID,
                       model: "mlx-community/Qwen3-8B-4bit", defaultPriority: 60, preferredProviderID: preferredProviderID)

        await addRoute(to: registry, role: .fastLocal, providerID: ModelDefaults.localMLXProviderID,
                       model: ModelDefaults.localMLXModelID, defaultPriority: 110, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .fastLocal, providerID: ModelDefaults.localOpenAIProviderID,
                       model: localRouteModel, defaultPriority: 100, preferredProviderID: preferredProviderID)

        await addRoute(to: registry, role: .memoryExtraction, providerID: ModelDefaults.localOpenAIProviderID,
                       model: ModelDefaults.phoneFunctionCallingModelID, defaultPriority: 120, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .memoryExtraction, providerID: ModelDefaults.openAIProviderID,
                       model: ModelDefaults.openAIUtilityModelID, defaultPriority: 100, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .memoryExtraction, providerID: ModelDefaults.openRouterProviderID,
                       model: ModelDefaults.openRouterUtilityModelID, defaultPriority: 90, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .memoryExtraction, providerID: ModelDefaults.localMLXProviderID,
                       model: ModelDefaults.localMLXFallbackModelID, defaultPriority: 75, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .memoryExtraction, providerID: ModelDefaults.localOpenAIProviderID,
                       model: localRouteModel, defaultPriority: 60, preferredProviderID: preferredProviderID)

        await addRoute(to: registry, role: .summarization, providerID: ModelDefaults.openAIProviderID,
                       model: ModelDefaults.openAIFastModelID, defaultPriority: 100, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .summarization, providerID: ModelDefaults.openRouterProviderID,
                       model: ModelDefaults.openRouterFastModelID, defaultPriority: 90, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .summarization, providerID: ModelDefaults.elizaCloudProviderID,
                       model: ModelDefaults.elizaCloudModelID, defaultPriority: 80, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .summarization, providerID: ModelDefaults.localMLXProviderID,
                       model: ModelDefaults.localMLXFallbackModelID, defaultPriority: 70, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .summarization, providerID: ModelDefaults.localOpenAIProviderID,
                       model: localRouteModel, defaultPriority: 60, preferredProviderID: preferredProviderID)

        await addRoute(to: registry, role: .embedding, providerID: ModelDefaults.localOpenAIProviderID,
                       model: "nomic-embed-text", defaultPriority: 110, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .embedding, providerID: ModelDefaults.localOpenAIProviderID,
                       model: "bge-m3", defaultPriority: 105, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .embedding, providerID: ModelDefaults.openAIProviderID,
                       model: ModelDefaults.openAIEmbeddingModelID, defaultPriority: 100, preferredProviderID: preferredProviderID)

        await addRoute(to: registry, role: .workflowPlanning, providerID: ModelDefaults.codexProviderID,
                       model: ModelDefaults.codexModelID, defaultPriority: 120, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .workflowPlanning, providerID: ModelDefaults.openAIProviderID,
                       model: ModelDefaults.openAIModelID, defaultPriority: 100, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .workflowPlanning, providerID: ModelDefaults.openRouterProviderID,
                       model: ModelDefaults.openRouterModelID, defaultPriority: 90, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .workflowPlanning, providerID: ModelDefaults.elizaCloudProviderID,
                       model: ModelDefaults.elizaCloudModelID, defaultPriority: 80, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .workflowPlanning, providerID: ModelDefaults.localMLXProviderID,
                       model: ModelDefaults.localMLXModelID, defaultPriority: 70, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .workflowPlanning, providerID: ModelDefaults.localOpenAIProviderID,
                       model: localRouteModel, defaultPriority: 60, preferredProviderID: preferredProviderID)

        await addRoute(to: registry, role: .toolCallRepair, providerID: ModelDefaults.localOpenAIProviderID,
                       model: ModelDefaults.phoneFunctionCallingModelID, defaultPriority: 120, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .toolCallRepair, providerID: ModelDefaults.openAIProviderID,
                       model: ModelDefaults.openAIUtilityModelID, defaultPriority: 100, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .toolCallRepair, providerID: ModelDefaults.openRouterProviderID,
                       model: ModelDefaults.openRouterUtilityModelID, defaultPriority: 90, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .toolCallRepair, providerID: ModelDefaults.localMLXProviderID,
                       model: "mlx-community/Qwen3-4B-4bit", defaultPriority: 80, preferredProviderID: preferredProviderID)
        await addRoute(to: registry, role: .toolCallRepair, providerID: ModelDefaults.localOpenAIProviderID,
                       model: localRouteModel, defaultPriority: 60, preferredProviderID: preferredProviderID)

        let router = ProviderRouter(registry: registry)
        return (router, registry)
    }

    /// Quick check: is any provider ready to use?
    public static func detectActiveProvider(
        secrets: any SecretStoring,
        preferredProviderID: String? = nil
    ) async -> (name: String, model: String)? {
        if let preferredProviderID,
           let preferred = await detectProvider(id: preferredProviderID, secrets: secrets) {
            return preferred
        }

        for id in [
            ModelDefaults.codexProviderID,
            ModelDefaults.openAIProviderID,
            ModelDefaults.openRouterProviderID,
            ModelDefaults.elizaCloudProviderID,
            ModelDefaults.localMLXProviderID,
            ModelDefaults.localOpenAIProviderID,
        ] {
            if let provider = await detectProvider(id: id, secrets: secrets) {
                return provider
            }
        }

        return nil
    }

    private static func priority(
        for providerID: String,
        defaultPriority: Int,
        preferredProviderID: String?
    ) -> Int {
        providerID == preferredProviderID ? defaultPriority + 1_000 : defaultPriority
    }

    private static func addRoute(
        to registry: ProviderRegistry,
        role: SwooshProviders.ModelRole,
        providerID: String,
        model: String,
        defaultPriority: Int,
        preferredProviderID: String?
    ) async {
        await registry.addRoute(ProviderRoute(
            role: role,
            providerID: ProviderID(providerID),
            model: model,
            priority: priority(
                for: providerID,
                defaultPriority: defaultPriority,
                preferredProviderID: preferredProviderID
            )
        ))
    }

    private static func localModelRouteDefault() async -> String {
        let configured = ProcessInfo.processInfo.environment["SWOOSH_LOCAL_MODEL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let configured, !configured.isEmpty {
            return configured
        }

        let discovery = LocalProviderDiscovery()
        if let model = await discovery.discover().first?.models.first {
            return model
        }

        let hardware = HardwareProfile.detectCurrent()
        return DynamicModelLoader.shared.defaultFallbackModel(hardware: hardware)
    }

    private static func detectProvider(
        id: String,
        secrets: any SecretStoring
    ) async -> (name: String, model: String)? {
        switch id {
        case "codex":
            let codex = CodexBridgeProvider()
            if await codex.isAuthenticated() {
                return ("ChatGPT (Codex)", ModelDefaults.codexModelID)
            }
        case "openai":
            if let _ = try? await secrets.get(SecretRef("openai", "api_key")) {
                return ("OpenAI", ModelDefaults.openAIModelID)
            }
        case "openrouter":
            if let _ = try? await secrets.get(SecretRef("openrouter", "api_key")) {
                return ("OpenRouter", ModelDefaults.openRouterModelID)
            }
        case "eliza-cloud":
            if let _ = try? await secrets.get(SecretRef("eliza-cloud", "api_key")) {
                return ("Eliza Cloud", ModelDefaults.elizaCloudModelID)
            }
        case "mlx-local":
            if MLXInferenceEngine.isAppleSilicon {
                return ("MLX Local", ModelDefaults.localMLXModelID)
            }
        case "local-openai":
            let discovery = LocalProviderDiscovery()
            let found = await discovery.discover()
            if let first = found.first, let model = first.models.first {
                return (first.name, model)
            }
        default:
            return nil
        }
        return nil
    }

    public static func providerID(forDetectedProviderName name: String) -> String {
        switch name {
        case "ChatGPT (Codex)":  return ModelDefaults.codexProviderID
        case "OpenAI":           return ModelDefaults.openAIProviderID
        case "OpenRouter":       return ModelDefaults.openRouterProviderID
        case "Eliza Cloud":      return ModelDefaults.elizaCloudProviderID
        case "Apple Foundation": return ModelDefaults.localFoundationProviderID
        case "MLX Local":        return ModelDefaults.localMLXProviderID
        default:                 return ModelDefaults.localOpenAIProviderID
        }
    }
}
