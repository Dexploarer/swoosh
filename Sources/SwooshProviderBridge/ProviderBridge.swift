// SwooshProviderBridge/ProviderBridge.swift — Bridge SwooshProviders → SwooshCore
//
// Adapts the real ProviderRouter to the SwooshCore ModelProvider protocol.
// Handles type conversion between SwooshCore.ChatMessage and SwooshTools.ChatMessage.
//
// Originally lived in SwooshCLI; promoted to its own library so the daemon
// can mount the real inference stack instead of LocalDiagnosticProvider.

import Foundation
import SwooshCore
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
    private let role: ModelRole

    public init(router: ProviderRouter, role: ModelRole = .primaryChat, modelName: String = "auto") {
        self.router = router
        self.role = role
        self.modelName = modelName
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
        let modelRequest = ModelRequest(
            model: request.model ?? modelName,
            messages: toolsMessages,
            tools: request.tools.map(Self.providerToolDescriptor)
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
        let openai = OpenAIResponsesProvider(secrets: secrets)
        await registry.register(openai, profile: .openAI)

        let openrouter = OpenRouterProvider(secrets: secrets)
        await registry.register(openrouter, profile: .openRouter)

        let eliza = ElizaCloudProvider(secrets: secrets)
        await registry.register(eliza, profile: .elizaCloud)

        let local = LocalOpenAICompatibleProvider()
        await registry.register(local, profile: .localOpenAI)

        await registry.addRoute(ProviderRoute(
            role: .primaryChat, providerID: ProviderID("openai"),
            model: "gpt-4.1", priority: priority(for: "openai", defaultPriority: 100, preferredProviderID: preferredProviderID)
        ))
        await registry.addRoute(ProviderRoute(
            role: .primaryChat, providerID: ProviderID("openrouter"),
            model: "openai/gpt-4.1", priority: priority(for: "openrouter", defaultPriority: 90, preferredProviderID: preferredProviderID)
        ))
        await registry.addRoute(ProviderRoute(
            role: .primaryChat, providerID: ProviderID("eliza-cloud"),
            model: "auto", priority: priority(for: "eliza-cloud", defaultPriority: 70, preferredProviderID: preferredProviderID)
        ))
        await registry.addRoute(ProviderRoute(
            role: .primaryChat, providerID: ProviderID("local-openai"),
            model: "llama3", priority: priority(for: "local-openai", defaultPriority: 60, preferredProviderID: preferredProviderID)
        ))

        // Coding routes
        await registry.addRoute(ProviderRoute(
            role: .coding, providerID: ProviderID("openai"),
            model: "gpt-4.1", priority: 100
        ))
        await registry.addRoute(ProviderRoute(
            role: .coding, providerID: ProviderID("openrouter"),
            model: "openai/gpt-4.1", priority: 90
        ))

        // Fast local
        await registry.addRoute(ProviderRoute(
            role: .fastLocal, providerID: ProviderID("local-openai"),
            model: "llama3", priority: 100
        ))

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

        for id in ["openai", "openrouter", "eliza-cloud", "local-openai"] {
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

    private static func detectProvider(
        id: String,
        secrets: any SecretStoring
    ) async -> (name: String, model: String)? {
        switch id {
        case "openai":
            if let _ = try? await secrets.get(SecretRef("openai", "api_key")) {
                return ("OpenAI", "gpt-4.1")
            }
        case "openrouter":
            if let _ = try? await secrets.get(SecretRef("openrouter", "api_key")) {
                return ("OpenRouter", "openai/gpt-4.1")
            }
        case "eliza-cloud":
            if let _ = try? await secrets.get(SecretRef("eliza-cloud", "api_key")) {
                return ("Eliza Cloud", "auto")
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
}
