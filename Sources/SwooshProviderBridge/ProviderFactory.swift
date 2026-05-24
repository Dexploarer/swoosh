// SwooshProviderBridge/ProviderFactory.swift — Provider stack bootstrap — 0.9B
//
// Builds the full `ProviderRouter` from Keychain secrets. The set of
// routes is data-driven via the `defaultRoutes` table — adding a new
// role / model is one row, not a new `await registry.addRoute(...)` call.

import Foundation
import SwooshMLX
import SwooshModels
import SwooshProviders
import SwooshSecrets
import SwooshTools

public struct ProviderFactory {

    /// One entry per (role, providerID, model, priority). The router
    /// iterates and registers each as a `ProviderRoute`. A
    /// `preferredProviderID` at runtime gets a +1000 boost so the user's
    /// pinned provider always wins ties.
    private struct RouteEntry: Sendable {
        let role: SwooshProviders.ModelRole
        let providerID: String
        let model: String
        let priority: Int
    }

    public static func buildRouter(
        secrets: any SecretStoring,
        preferredProviderID: String? = nil
    ) async -> (ProviderRouter, ProviderRegistry) {
        let registry = ProviderRegistry()
        await registerAllProviders(registry, secrets: secrets)
        let localRouteModel = await localModelRouteDefault()
        for entry in defaultRoutes(localRouteModel: localRouteModel) {
            await registry.addRoute(ProviderRoute(
                role: entry.role,
                providerID: ProviderID(entry.providerID),
                model: entry.model,
                priority: priority(
                    for: entry.providerID,
                    defaultPriority: entry.priority,
                    preferredProviderID: preferredProviderID
                )
            ))
        }
        let router = ProviderRouter(registry: registry)
        return (router, registry)
    }

    private static func registerAllProviders(
        _ registry: ProviderRegistry,
        secrets: any SecretStoring
    ) async {
        await registry.register(CodexBridgeProvider(), profile: .codex)
        await registry.register(OpenAIResponsesProvider(secrets: secrets), profile: .openAI)
        await registry.register(OpenRouterProvider(secrets: secrets), profile: .openRouter)
        await registry.register(ElizaCloudProvider(secrets: secrets), profile: .elizaCloud)
        await registry.register(MLXLocalProvider(), profile: .mlxLocal)
        await registry.register(LocalOpenAICompatibleProvider(), profile: .localOpenAI)
    }

    // MARK: - Route table

    private static func defaultRoutes(localRouteModel: String) -> [RouteEntry] {
        primaryChatRoutes(localRouteModel: localRouteModel)
            + codingRoutes(localRouteModel: localRouteModel)
            + fastLocalRoutes(localRouteModel: localRouteModel)
            + memoryExtractionRoutes(localRouteModel: localRouteModel)
            + summarizationRoutes(localRouteModel: localRouteModel)
            + embeddingRoutes
            + workflowPlanningRoutes(localRouteModel: localRouteModel)
            + toolCallRepairRoutes(localRouteModel: localRouteModel)
    }

    private static func primaryChatRoutes(localRouteModel: String) -> [RouteEntry] {
        [
            RouteEntry(role: .primaryChat, providerID: ModelDefaults.codexProviderID,
                       model: ModelDefaults.codexModelID, priority: 120),
            RouteEntry(role: .primaryChat, providerID: ModelDefaults.openAIProviderID,
                       model: ModelDefaults.openAIModelID, priority: 100),
            RouteEntry(role: .primaryChat, providerID: ModelDefaults.openRouterProviderID,
                       model: ModelDefaults.openRouterModelID, priority: 90),
            RouteEntry(role: .primaryChat, providerID: ModelDefaults.elizaCloudProviderID,
                       model: ModelDefaults.elizaCloudModelID, priority: 70),
            RouteEntry(role: .primaryChat, providerID: ModelDefaults.localMLXProviderID,
                       model: ModelDefaults.localMLXModelID, priority: 65),
            RouteEntry(role: .primaryChat, providerID: ModelDefaults.localOpenAIProviderID,
                       model: localRouteModel, priority: 60)
        ]
    }

    private static func codingRoutes(localRouteModel: String) -> [RouteEntry] {
        [
            RouteEntry(role: .coding, providerID: ModelDefaults.codexProviderID,
                       model: ModelDefaults.codexModelID, priority: 110),
            RouteEntry(role: .coding, providerID: ModelDefaults.openAIProviderID,
                       model: ModelDefaults.openAICodingModelID, priority: 100),
            RouteEntry(role: .coding, providerID: ModelDefaults.openRouterProviderID,
                       model: ModelDefaults.openRouterCodingModelID, priority: 90),
            RouteEntry(role: .coding, providerID: ModelDefaults.localOpenAIProviderID,
                       model: "qwen3-coder-next", priority: 70),
            RouteEntry(role: .coding, providerID: ModelDefaults.localMLXProviderID,
                       model: "mlx-community/Qwen3-8B-4bit", priority: 60),
            RouteEntry(role: .coding, providerID: ModelDefaults.localOpenAIProviderID,
                       model: localRouteModel, priority: 55)
        ]
    }

    private static func fastLocalRoutes(localRouteModel: String) -> [RouteEntry] {
        [
            RouteEntry(role: .fastLocal, providerID: ModelDefaults.localMLXProviderID,
                       model: ModelDefaults.localMLXModelID, priority: 110),
            RouteEntry(role: .fastLocal, providerID: ModelDefaults.localOpenAIProviderID,
                       model: localRouteModel, priority: 100)
        ]
    }

    private static func memoryExtractionRoutes(localRouteModel: String) -> [RouteEntry] {
        [
            RouteEntry(role: .memoryExtraction, providerID: ModelDefaults.localOpenAIProviderID,
                       model: ModelDefaults.phoneFunctionCallingModelID, priority: 120),
            RouteEntry(role: .memoryExtraction, providerID: ModelDefaults.openAIProviderID,
                       model: ModelDefaults.openAIUtilityModelID, priority: 100),
            RouteEntry(role: .memoryExtraction, providerID: ModelDefaults.openRouterProviderID,
                       model: ModelDefaults.openRouterUtilityModelID, priority: 90),
            RouteEntry(role: .memoryExtraction, providerID: ModelDefaults.localMLXProviderID,
                       model: ModelDefaults.localMLXFallbackModelID, priority: 75),
            RouteEntry(role: .memoryExtraction, providerID: ModelDefaults.localOpenAIProviderID,
                       model: localRouteModel, priority: 60)
        ]
    }

    private static func summarizationRoutes(localRouteModel: String) -> [RouteEntry] {
        [
            RouteEntry(role: .summarization, providerID: ModelDefaults.openAIProviderID,
                       model: ModelDefaults.openAIFastModelID, priority: 100),
            RouteEntry(role: .summarization, providerID: ModelDefaults.openRouterProviderID,
                       model: ModelDefaults.openRouterFastModelID, priority: 90),
            RouteEntry(role: .summarization, providerID: ModelDefaults.elizaCloudProviderID,
                       model: ModelDefaults.elizaCloudModelID, priority: 80),
            RouteEntry(role: .summarization, providerID: ModelDefaults.localMLXProviderID,
                       model: ModelDefaults.localMLXFallbackModelID, priority: 70),
            RouteEntry(role: .summarization, providerID: ModelDefaults.localOpenAIProviderID,
                       model: localRouteModel, priority: 60)
        ]
    }

    private static let embeddingRoutes: [RouteEntry] = [
        RouteEntry(role: .embedding, providerID: ModelDefaults.localOpenAIProviderID,
                   model: "nomic-embed-text", priority: 110),
        RouteEntry(role: .embedding, providerID: ModelDefaults.localOpenAIProviderID,
                   model: "bge-m3", priority: 105),
        RouteEntry(role: .embedding, providerID: ModelDefaults.openAIProviderID,
                   model: ModelDefaults.openAIEmbeddingModelID, priority: 100)
    ]

    private static func workflowPlanningRoutes(localRouteModel: String) -> [RouteEntry] {
        [
            RouteEntry(role: .workflowPlanning, providerID: ModelDefaults.codexProviderID,
                       model: ModelDefaults.codexModelID, priority: 120),
            RouteEntry(role: .workflowPlanning, providerID: ModelDefaults.openAIProviderID,
                       model: ModelDefaults.openAIModelID, priority: 100),
            RouteEntry(role: .workflowPlanning, providerID: ModelDefaults.openRouterProviderID,
                       model: ModelDefaults.openRouterModelID, priority: 90),
            RouteEntry(role: .workflowPlanning, providerID: ModelDefaults.elizaCloudProviderID,
                       model: ModelDefaults.elizaCloudModelID, priority: 80),
            RouteEntry(role: .workflowPlanning, providerID: ModelDefaults.localMLXProviderID,
                       model: ModelDefaults.localMLXModelID, priority: 70),
            RouteEntry(role: .workflowPlanning, providerID: ModelDefaults.localOpenAIProviderID,
                       model: localRouteModel, priority: 60)
        ]
    }

    private static func toolCallRepairRoutes(localRouteModel: String) -> [RouteEntry] {
        [
            RouteEntry(role: .toolCallRepair, providerID: ModelDefaults.localOpenAIProviderID,
                       model: ModelDefaults.phoneFunctionCallingModelID, priority: 120),
            RouteEntry(role: .toolCallRepair, providerID: ModelDefaults.openAIProviderID,
                       model: ModelDefaults.openAIUtilityModelID, priority: 100),
            RouteEntry(role: .toolCallRepair, providerID: ModelDefaults.openRouterProviderID,
                       model: ModelDefaults.openRouterUtilityModelID, priority: 90),
            RouteEntry(role: .toolCallRepair, providerID: ModelDefaults.localMLXProviderID,
                       model: "mlx-community/Qwen3-4B-4bit", priority: 80),
            RouteEntry(role: .toolCallRepair, providerID: ModelDefaults.localOpenAIProviderID,
                       model: localRouteModel, priority: 60)
        ]
    }

    // MARK: - Detection

    public static func detectActiveProvider(
        secrets: any SecretStoring,
        preferredProviderID: String? = nil
    ) async -> (name: String, model: String)? {
        if let preferredProviderID,
           let preferred = await detectProvider(id: preferredProviderID, secrets: secrets) {
            return preferred
        }
        let order = [
            ModelDefaults.codexProviderID,
            ModelDefaults.openAIProviderID,
            ModelDefaults.openRouterProviderID,
            ModelDefaults.elizaCloudProviderID,
            ModelDefaults.localMLXProviderID,
            ModelDefaults.localOpenAIProviderID
        ]
        for id in order {
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

    /// Resolve the default local-OpenAI-compatible model: env override
    /// `SWOOSH_LOCAL_MODEL` wins, otherwise the first model from an
    /// already-running local provider, otherwise the hardware-aware
    /// default from `DynamicModelLoader`.
    static func localModelRouteDefault() async -> String {
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

    /// Dispatch to a per-provider detector helper. Splitting cuts the
    /// cyclomatic complexity of any single function below the strict
    /// linter limit and lets each helper own its own happy-path logic.
    private static func detectProvider(
        id: String,
        secrets: any SecretStoring
    ) async -> (name: String, model: String)? {
        switch id {
        case ModelDefaults.codexProviderID: return await detectCodex()
        case ModelDefaults.openAIProviderID: return await detectOpenAI(secrets: secrets)
        case ModelDefaults.openRouterProviderID: return await detectOpenRouter(secrets: secrets)
        case ModelDefaults.elizaCloudProviderID: return await detectElizaCloud(secrets: secrets)
        case ModelDefaults.localMLXProviderID: return detectMLXLocal()
        case ModelDefaults.localOpenAIProviderID: return await detectLocalOpenAI()
        default: return nil
        }
    }

    private static func detectCodex() async -> (name: String, model: String)? {
        let codex = CodexBridgeProvider()
        guard await codex.isAuthenticated() else { return nil }
        return ("ChatGPT (Codex)", ModelDefaults.codexModelID)
    }

    private static func detectOpenAI(
        secrets: any SecretStoring
    ) async -> (name: String, model: String)? {
        guard (try? await secrets.get(SecretRef("openai", "api_key"))) != nil else { return nil }
        return ("OpenAI", ModelDefaults.openAIModelID)
    }

    private static func detectOpenRouter(
        secrets: any SecretStoring
    ) async -> (name: String, model: String)? {
        guard (try? await secrets.get(SecretRef("openrouter", "api_key"))) != nil else {
            return nil
        }
        return ("OpenRouter", ModelDefaults.openRouterModelID)
    }

    private static func detectElizaCloud(
        secrets: any SecretStoring
    ) async -> (name: String, model: String)? {
        guard (try? await secrets.get(SecretRef("eliza-cloud", "api_key"))) != nil else {
            return nil
        }
        return ("Eliza Cloud", ModelDefaults.elizaCloudModelID)
    }

    private static func detectMLXLocal() -> (name: String, model: String)? {
        guard MLXInferenceEngine.isAppleSilicon else { return nil }
        return ("MLX Local", ModelDefaults.localMLXModelID)
    }

    private static func detectLocalOpenAI() async -> (name: String, model: String)? {
        let discovery = LocalProviderDiscovery()
        let found = await discovery.discover()
        guard let first = found.first, let model = first.models.first else { return nil }
        return (first.name, model)
    }

    /// Reverse mapping for `detectActiveProvider` output: turn the
    /// human-readable name back into the canonical provider ID. The two
    /// must stay in sync — if `detectProvider` emits a new name, add it
    /// here. Cases that don't appear in any branch of `detectProvider`
    /// were removed (specifically "Apple Foundation" — that provider is
    /// not currently part of the detection chain).
    public static func providerID(forDetectedProviderName name: String) -> String {
        switch name {
        case "ChatGPT (Codex)": return ModelDefaults.codexProviderID
        case "OpenAI": return ModelDefaults.openAIProviderID
        case "OpenRouter": return ModelDefaults.openRouterProviderID
        case "Eliza Cloud": return ModelDefaults.elizaCloudProviderID
        case "MLX Local": return ModelDefaults.localMLXProviderID
        default: return ModelDefaults.localOpenAIProviderID
        }
    }
}
