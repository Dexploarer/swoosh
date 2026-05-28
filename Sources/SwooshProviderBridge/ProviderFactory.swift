// SwooshProviderBridge/ProviderFactory.swift — Provider stack bootstrap — 0.9B
//
// Builds the full `ProviderRouter` from Keychain secrets. The set of
// routes is data-driven via the `defaultRoutes` table — adding a new
// role / model is one row, not a new `await registry.addRoute(...)` call.

import Foundation
#if canImport(SwooshMLX)
import SwooshMLX
#endif
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
        await registry.register(AnthropicProvider(secrets: secrets), profile: .anthropic)
        await registry.register(OpenRouterProvider(secrets: secrets), profile: .openRouter)
        await registry.register(DetourCloudProvider(secrets: secrets), profile: .detourCloud)
        #if canImport(SwooshMLX)
        await registry.register(MLXLocalProvider(), profile: .mlxLocal)
        #endif
        await registry.register(LocalOpenAICompatibleProvider(), profile: .localOpenAI)

        // Dev proxy — a localhost OpenAI-compatible endpoint with a Bearer
        // key (rotates free tiers). Reuses LocalOpenAICompatibleProvider
        // under its own providerID. Key resolved from Keychain at build
        // time; the provider only sends it when present.
        let devProxyKey = try? await secrets.get(SecretRef("dev-proxy", "api_key"))
        await registry.register(
            LocalOpenAICompatibleProvider(
                baseURL: ModelDefaults.devProxyBaseURL,
                providerID: ProviderID(ModelDefaults.devProxyProviderID),
                displayName: "Dev Proxy (free tiers)",
                apiKey: devProxyKey
            ),
            profile: .devProxy
        )
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
            + devProxyRoutes()
    }

    /// One dev-proxy route per text role so that selecting the dev proxy
    /// (which gives it the +1000 preferred boost) routes every text query
    /// through localhost:3001. Embeddings are intentionally excluded —
    /// they stay on the local/OpenAI embedding routes.
    private static func devProxyRoutes() -> [RouteEntry] {
        let textRoles: [SwooshProviders.ModelRole] = [
            .primaryChat, .coding, .fastLocal, .memoryExtraction,
            .summarization, .workflowPlanning, .toolCallRepair,
        ]
        return textRoles.map { role in
            RouteEntry(
                role: role,
                providerID: ModelDefaults.devProxyProviderID,
                model: role == .coding ? ModelDefaults.devProxyCodingModelID : ModelDefaults.devProxyModelID,
                priority: 64
            )
        }
    }

    private static func primaryChatRoutes(localRouteModel: String) -> [RouteEntry] {
        [
            RouteEntry(role: .primaryChat, providerID: ModelDefaults.codexProviderID,
                       model: ModelDefaults.codexModelID, priority: 120),
            RouteEntry(role: .primaryChat, providerID: ModelDefaults.openAIProviderID,
                       model: ModelDefaults.openAIModelID, priority: 100),
            RouteEntry(role: .primaryChat, providerID: ModelDefaults.anthropicProviderID,
                       model: ModelDefaults.anthropicModelID, priority: 95),
            RouteEntry(role: .primaryChat, providerID: ModelDefaults.openRouterProviderID,
                       model: ModelDefaults.openRouterModelID, priority: 90),
            RouteEntry(role: .primaryChat, providerID: ModelDefaults.detourCloudProviderID,
                       model: ModelDefaults.detourCloudModelID, priority: 70),
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
            RouteEntry(role: .coding, providerID: ModelDefaults.anthropicProviderID,
                       model: ModelDefaults.anthropicCodingModelID, priority: 95),
            RouteEntry(role: .coding, providerID: ModelDefaults.openRouterProviderID,
                       model: ModelDefaults.openRouterCodingModelID, priority: 90),
            RouteEntry(role: .coding, providerID: ModelDefaults.localOpenAIProviderID,
                       model: "qwen3-coder-next", priority: 70),
            RouteEntry(role: .coding, providerID: ModelDefaults.localMLXProviderID,
                       model: "mlx-community/Qwen3.5-8B-4bit", priority: 60),
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
            RouteEntry(role: .summarization, providerID: ModelDefaults.detourCloudProviderID,
                       model: ModelDefaults.detourCloudModelID, priority: 80),
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
            RouteEntry(role: .workflowPlanning, providerID: ModelDefaults.detourCloudProviderID,
                       model: ModelDefaults.detourCloudModelID, priority: 80),
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
                       model: "mlx-community/Qwen3.5-4B-4bit", priority: 80),
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
            ModelDefaults.anthropicProviderID,
            ModelDefaults.openRouterProviderID,
            ModelDefaults.detourCloudProviderID,
            ModelDefaults.devProxyProviderID,
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
        case ModelDefaults.anthropicProviderID: return await detectAnthropic(secrets: secrets)
        case ModelDefaults.openRouterProviderID: return await detectOpenRouter(secrets: secrets)
        case ModelDefaults.detourCloudProviderID: return await detectDetourCloud(secrets: secrets)
        case ModelDefaults.devProxyProviderID: return await detectDevProxy(secrets: secrets)
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

    private static func detectAnthropic(
        secrets: any SecretStoring
    ) async -> (name: String, model: String)? {
        guard (try? await secrets.get(SecretRef("anthropic", "api_key"))) != nil else {
            return nil
        }
        return ("Anthropic (Claude)", ModelDefaults.anthropicModelID)
    }

    private static func detectOpenRouter(
        secrets: any SecretStoring
    ) async -> (name: String, model: String)? {
        guard (try? await secrets.get(SecretRef("openrouter", "api_key"))) != nil else {
            return nil
        }
        return ("OpenRouter", ModelDefaults.openRouterModelID)
    }

    private static func detectDetourCloud(
        secrets: any SecretStoring
    ) async -> (name: String, model: String)? {
        guard (try? await secrets.get(SecretRef("detour-cloud", "api_key"))) != nil else {
            return nil
        }
        return ("Detour Cloud", ModelDefaults.detourCloudModelID)
    }

    private static func detectDevProxy(
        secrets: any SecretStoring
    ) async -> (name: String, model: String)? {
        guard (try? await secrets.get(SecretRef("dev-proxy", "api_key"))) != nil else {
            return nil
        }
        return ("Dev Proxy (free tiers)", ModelDefaults.devProxyModelID)
    }

    private static func detectMLXLocal() -> (name: String, model: String)? {
        #if canImport(SwooshMLX)
        guard MLXInferenceEngine.isAppleSilicon else { return nil }

        // SwiftPM command-line builds do not compile metal shaders into default.metallib,
        // causing MLX to crash at runtime when initialized. Check that the compiled metal
        // shaders exist in at least one bundle before advertising MLX support.
        let hasMetallib = Bundle.allBundles.contains { bundle in
            bundle.url(forResource: "default", withExtension: "metallib") != nil
        }
        guard hasMetallib else { return nil }

        let explicitModel = ProcessInfo.processInfo.environment["SWOOSH_MLX_MODEL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let model = (explicitModel != nil && !explicitModel!.isEmpty) ? explicitModel! : ModelDefaults.localMLXModelID

        return ("MLX Local", model)
        #else
        return nil
        #endif
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
        case "Anthropic (Claude)": return ModelDefaults.anthropicProviderID
        case "OpenRouter": return ModelDefaults.openRouterProviderID
        case "Detour Cloud", "Eliza Cloud": return ModelDefaults.detourCloudProviderID
        case "Dev Proxy (free tiers)": return ModelDefaults.devProxyProviderID
        case "MLX Local": return ModelDefaults.localMLXProviderID
        case "Apple Foundation": return ModelDefaults.localFoundationProviderID
        default: return ModelDefaults.localOpenAIProviderID
        }
    }
}
