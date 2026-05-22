// SwooshModels/UnifiedModelCatalog.swift - Canonical model defaults and registry - 0.9S

import Foundation

public enum ModelRuntimeKind: String, Codable, Sendable, CaseIterable {
    case router
    case codex
    case openAI
    case openRouter
    case elizaCloud
    case localOpenAI
    case localMLX
    case localLiteRT
    case localFoundation
}

public struct UnifiedModelEntry: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let modelID: String
    public let providerID: String
    public let displayName: String
    public let family: String
    public let runtime: ModelRuntimeKind
    public let contextWindow: Int?
    public let estimatedMemoryGB: Double?
    public let capabilities: Set<ModelCapability>
    public let roles: Set<ModelRole>
    public let supportsReasoningEffort: Bool
    public let blurb: String
    public let installCommands: [ModelSource: String]

    public init(
        id: String,
        modelID: String,
        providerID: String,
        displayName: String,
        family: String,
        runtime: ModelRuntimeKind,
        contextWindow: Int? = nil,
        estimatedMemoryGB: Double? = nil,
        capabilities: Set<ModelCapability>,
        roles: Set<ModelRole>,
        supportsReasoningEffort: Bool = false,
        blurb: String,
        installCommands: [ModelSource: String] = [:]
    ) {
        self.id = id
        self.modelID = modelID
        self.providerID = providerID
        self.displayName = displayName
        self.family = family
        self.runtime = runtime
        self.contextWindow = contextWindow
        self.estimatedMemoryGB = estimatedMemoryGB
        self.capabilities = capabilities
        self.roles = roles
        self.supportsReasoningEffort = supportsReasoningEffort
        self.blurb = blurb
        self.installCommands = installCommands
    }
}

public enum ModelDefaults {
    public static let routerProviderID = "router"
    public static let routerModelID = "auto"
    public static let defaultInteractiveModelID = "auto"

    public static let codexProviderID = "codex"
    public static let codexModelID = "auto"

    public static let openAIProviderID = "openai"
    public static let openAIModelID = "gpt-5.5"
    public static let openAICodingModelID = "gpt-5.2-codex"
    public static let openAIFastModelID = "gpt-5-mini"
    public static let openAIUtilityModelID = "gpt-5-nano"
    public static let openAIEmbeddingModelID = "text-embedding-3-small"

    public static let openRouterProviderID = "openrouter"
    public static let openRouterModelID = "openai/gpt-5.5"
    public static let openRouterCodingModelID = "openai/gpt-5.2-codex"
    public static let openRouterFastModelID = "openai/gpt-5-mini"
    public static let openRouterUtilityModelID = "openai/gpt-5-nano"

    public static let elizaCloudProviderID = "eliza-cloud"
    public static let elizaCloudModelID = "auto"

    public static let localOpenAIProviderID = "local-openai"
    public static let localOpenAIModelID = "gemma4:e4b"
    public static let localOpenAIFallbackModelID = "gemma4:e2b"
    public static let phoneFunctionCallingModelID = "functiongemma:270m"

    public static let localMLXProviderID = "mlx-local"
    public static let localMLXModelID = "mlx-community/gemma-4-e4b-it-4bit"
    public static let localMLXFallbackModelID = "mlx-community/gemma-4-e2b-it-4bit"
    public static let localLiteRTProviderID = "litert-local"
    public static let localLiteRTModelID = "gemma-4-E4B-it"
    public static let localFoundationProviderID = "apple-foundation"
    public static let localFoundationModelID = "apple-on-device"
}

public enum UnifiedModelCatalog {
    public static var all: [UnifiedModelEntry] {
        cloud + localMLX + local
    }

    public static var interactive: [UnifiedModelEntry] {
        all.filter { entry in
            entry.capabilities.contains(.textGeneration)
            && !entry.capabilities.contains(.embedding)
            && !entry.capabilities.contains(.speechToText)
            && !entry.capabilities.contains(.textToSpeech)
            && !entry.capabilities.contains(.imageGeneration)
            && !entry.capabilities.contains(.reranking)
            && entry.providerID != ModelDefaults.localFoundationProviderID
            && (entry.roles.contains(.agent) || entry.roles.contains(.coder) || entry.roles.contains(.vision))
        }
    }

    public static var embeddings: [UnifiedModelEntry] {
        models(withCapability: .embedding)
    }

    public static var rerankers: [UnifiedModelEntry] {
        models(withCapability: .reranking)
    }

    public static var speechToText: [UnifiedModelEntry] {
        models(withCapability: .speechToText)
    }

    public static var textToSpeech: [UnifiedModelEntry] {
        models(withCapability: .textToSpeech)
    }

    public static var imageGeneration: [UnifiedModelEntry] {
        models(withCapability: .imageGeneration)
    }

    public static func models(withRole role: ModelRole) -> [UnifiedModelEntry] {
        all.filter { $0.roles.contains(role) }
    }

    public static func models(withCapability capability: ModelCapability) -> [UnifiedModelEntry] {
        all.filter { $0.capabilities.contains(capability) }
    }

    public static var cloud: [UnifiedModelEntry] {
        CloudCatalog.all.map { entry in
            UnifiedModelEntry(
                id: entry.id,
                modelID: entry.routeModelID,
                providerID: entry.providerID,
                displayName: entry.displayName,
                family: entry.family,
                runtime: runtime(for: entry.providerID),
                contextWindow: entry.contextWindow,
                capabilities: cloudCapabilities(entry),
                roles: [.agent, .coder, .fallback],
                supportsReasoningEffort: entry.supportsReasoningEffort,
                blurb: entry.blurb
            )
        }
    }

    public static var local: [UnifiedModelEntry] {
        ModelCatalog.curatedModels.map { entry in
            let providerID = providerID(for: entry)
            return UnifiedModelEntry(
                id: "\(providerID):\(entry.ollamaTag ?? entry.id)",
                modelID: entry.ollamaTag ?? entry.id,
                providerID: providerID,
                displayName: entry.name,
                family: entry.family,
                runtime: runtime(forLocalProviderID: providerID),
                estimatedMemoryGB: entry.estimatedMemoryGB,
                capabilities: entry.capabilities,
                roles: entry.defaultRoles,
                blurb: entry.description,
                installCommands: entry.installCommands
            )
        }
    }

    public static var localMLX: [UnifiedModelEntry] {
        [
            mlxEntry(
                id: "gemma4-e4b",
                modelID: ModelDefaults.localMLXModelID,
                displayName: "Gemma 4 E4B (MLX Swift)",
                family: "Gemma 4",
                estimatedMemoryGB: 9.6,
                capabilities: [.textGeneration, .coding, .structuredOutput, .vision, .ocr],
                roles: [.agent, .coder, .vision],
                blurb: "Default Mac-local Gemma 4 route through mlx-swift-lm."
            ),
            mlxEntry(
                id: "gemma4-e2b",
                modelID: ModelDefaults.localMLXFallbackModelID,
                displayName: "Gemma 4 E2B (MLX Swift)",
                family: "Gemma 4",
                estimatedMemoryGB: 7.2,
                capabilities: [.textGeneration, .coding, .structuredOutput, .vision, .ocr],
                roles: [.agent, .coder, .vision],
                blurb: "Smaller Gemma 4 Mac-local fallback for tighter memory budgets."
            ),
            mlxEntry(
                id: "qwen3-8b",
                modelID: "mlx-community/Qwen3-8B-4bit",
                displayName: "Qwen3 8B (MLX Swift)",
                family: "Qwen3",
                estimatedMemoryGB: 5.5,
                capabilities: [.textGeneration, .coding, .toolCalling, .structuredOutput],
                roles: [.agent, .coder],
                blurb: "MLX Swift Qwen route for fast local agent work."
            ),
            mlxEntry(
                id: "qwen3-4b",
                modelID: "mlx-community/Qwen3-4B-4bit",
                displayName: "Qwen3 4B (MLX Swift)",
                family: "Qwen3",
                estimatedMemoryGB: 3.0,
                capabilities: [.textGeneration, .coding, .toolCalling, .structuredOutput],
                roles: [.agent, .coder],
                blurb: "Small MLX Swift Qwen route for low-latency local chat."
            ),
            mlxEntry(
                id: "qwen3-30b-a3b",
                modelID: "mlx-community/Qwen3-30B-A3B-4bit",
                displayName: "Qwen3 30B A3B (MLX Swift)",
                family: "Qwen3",
                estimatedMemoryGB: 18.0,
                capabilities: [.textGeneration, .coding, .toolCalling, .structuredOutput],
                roles: [.agent, .coder],
                blurb: "MLX Swift MoE Qwen route for high-memory Macs."
            ),
        ]
    }

    public static func providerDisplayName(_ providerID: String) -> String {
        switch providerID {
        case ModelDefaults.routerProviderID: return "Auto"
        case ModelDefaults.codexProviderID: return "ChatGPT"
        case ModelDefaults.openAIProviderID: return "OpenAI"
        case ModelDefaults.openRouterProviderID: return "OpenRouter"
        case ModelDefaults.elizaCloudProviderID: return "Eliza Cloud"
        case ModelDefaults.localOpenAIProviderID: return "Ollama / Local OpenAI"
        case ModelDefaults.localMLXProviderID: return "MLX Local"
        case ModelDefaults.localLiteRTProviderID: return "LiteRT Local"
        case ModelDefaults.localFoundationProviderID: return "Apple Foundation"
        default: return providerID.capitalized
        }
    }

    public static func defaultModel(providerID: String) -> String? {
        switch providerID {
        case ModelDefaults.codexProviderID: return ModelDefaults.codexModelID
        case ModelDefaults.openAIProviderID: return ModelDefaults.openAIModelID
        case ModelDefaults.openRouterProviderID: return ModelDefaults.openRouterModelID
        case ModelDefaults.elizaCloudProviderID: return ModelDefaults.elizaCloudModelID
        case ModelDefaults.localOpenAIProviderID: return ModelDefaults.localOpenAIModelID
        case ModelDefaults.localMLXProviderID: return ModelDefaults.localMLXModelID
        case ModelDefaults.localLiteRTProviderID: return ModelDefaults.localLiteRTModelID
        case ModelDefaults.localFoundationProviderID: return ModelDefaults.localFoundationModelID
        default: return nil
        }
    }

    public static func route(forCatalogID id: String) -> (providerID: String, modelID: String)? {
        guard let entry = all.first(where: { $0.id == id }) else { return nil }
        guard entry.providerID != ModelDefaults.routerProviderID else { return nil }
        guard entry.capabilities.contains(.textGeneration) else { return nil }
        return (entry.providerID, entry.modelID)
    }

    private static func providerID(for entry: CatalogEntry) -> String {
        if entry.sources.contains(.ollama) { return ModelDefaults.localOpenAIProviderID }
        if entry.sources.contains(.mlxCommunity) { return ModelDefaults.localMLXProviderID }
        if entry.sources.contains(.system) { return ModelDefaults.localFoundationProviderID }
        return ModelDefaults.localOpenAIProviderID
    }

    private static func runtime(for providerID: String) -> ModelRuntimeKind {
        switch providerID {
        case ModelDefaults.routerProviderID: return .router
        case ModelDefaults.codexProviderID: return .codex
        case ModelDefaults.openAIProviderID: return .openAI
        case ModelDefaults.openRouterProviderID: return .openRouter
        case ModelDefaults.elizaCloudProviderID: return .elizaCloud
        default: return .openRouter
        }
    }

    private static func runtime(forLocalProviderID providerID: String) -> ModelRuntimeKind {
        switch providerID {
        case ModelDefaults.localMLXProviderID: return .localMLX
        case ModelDefaults.localLiteRTProviderID: return .localLiteRT
        case ModelDefaults.localFoundationProviderID: return .localFoundation
        default: return .localOpenAI
        }
    }

    private static func cloudCapabilities(_ entry: CloudModelEntry) -> Set<ModelCapability> {
        var capabilities: Set<ModelCapability> = [.textGeneration]
        if entry.supportsToolCalling { capabilities.insert(.toolCalling) }
        if entry.supportsVision { capabilities.insert(.vision) }
        return capabilities
    }

    private static func mlxEntry(
        id: String,
        modelID: String,
        displayName: String,
        family: String,
        estimatedMemoryGB: Double,
        capabilities: Set<ModelCapability>,
        roles: Set<ModelRole>,
        blurb: String
    ) -> UnifiedModelEntry {
        UnifiedModelEntry(
            id: "\(ModelDefaults.localMLXProviderID):\(id)",
            modelID: modelID,
            providerID: ModelDefaults.localMLXProviderID,
            displayName: displayName,
            family: family,
            runtime: .localMLX,
            estimatedMemoryGB: estimatedMemoryGB,
            capabilities: capabilities,
            roles: roles,
            blurb: blurb,
            installCommands: [
                .mlxCommunity: "huggingface-cli download \(modelID)"
            ]
        )
    }
}
