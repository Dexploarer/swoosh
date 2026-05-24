// SwooshModels/CloudCatalog.swift — Wired cloud model catalog — 0.9T

import Foundation

public struct CloudModelEntry: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let routeModelID: String
    public let displayName: String
    public let family: String
    public let providerID: String
    public let contextWindow: Int
    public let supportsReasoningEffort: Bool
    public let supportsToolCalling: Bool
    public let supportsVision: Bool
    public let isFamilyDefault: Bool
    public let blurb: String

    public init(
        id: String,
        routeModelID: String? = nil,
        displayName: String,
        family: String,
        providerID: String,
        contextWindow: Int,
        supportsReasoningEffort: Bool,
        supportsToolCalling: Bool,
        supportsVision: Bool,
        isFamilyDefault: Bool,
        blurb: String
    ) {
        self.id = id
        self.routeModelID = routeModelID ?? id
        self.displayName = displayName
        self.family = family
        self.providerID = providerID
        self.contextWindow = contextWindow
        self.supportsReasoningEffort = supportsReasoningEffort
        self.supportsToolCalling = supportsToolCalling
        self.supportsVision = supportsVision
        self.isFamilyDefault = isFamilyDefault
        self.blurb = blurb
    }
}

public enum CloudCatalog {
    public static let router: [CloudModelEntry] = [
        CloudModelEntry(
            id: ModelDefaults.routerModelID,
            displayName: "Auto",
            family: "Swoosh Router",
            providerID: ModelDefaults.routerProviderID,
            contextWindow: 0,
            supportsReasoningEffort: false,
            supportsToolCalling: true,
            supportsVision: true,
            isFamilyDefault: true,
            blurb: "Use the daemon's provider priority and fallback chain."
        ),
    ]

    public static let codex: [CloudModelEntry] = [
        CloudModelEntry(
            id: "codex-auto",
            routeModelID: ModelDefaults.codexModelID,
            displayName: "ChatGPT (Codex)",
            family: "ChatGPT",
            providerID: ModelDefaults.codexProviderID,
            contextWindow: 0,
            supportsReasoningEffort: false,
            supportsToolCalling: false,
            supportsVision: false,
            isFamilyDefault: true,
            blurb: "Uses the local Codex CLI and ChatGPT account session."
        ),
    ]

    public static let openAI: [CloudModelEntry] = [
        CloudModelEntry(
            id: ModelDefaults.openAIModelID,
            displayName: "GPT-5.5",
            family: "GPT-5",
            providerID: ModelDefaults.openAIProviderID,
            contextWindow: 400_000,
            supportsReasoningEffort: true,
            supportsToolCalling: true,
            supportsVision: true,
            isFamilyDefault: true,
            blurb: "Default OpenAI Platform model for coding and agentic tasks."
        ),
        CloudModelEntry(
            id: "gpt-5.2",
            displayName: "GPT-5.2",
            family: "GPT-5",
            providerID: ModelDefaults.openAIProviderID,
            contextWindow: 400_000,
            supportsReasoningEffort: true,
            supportsToolCalling: true,
            supportsVision: true,
            isFamilyDefault: false,
            blurb: "Previous OpenAI reasoning model."
        ),
        CloudModelEntry(
            id: ModelDefaults.openAICodingModelID,
            displayName: "GPT-5.2 Codex",
            family: "GPT-5",
            providerID: ModelDefaults.openAIProviderID,
            contextWindow: 400_000,
            supportsReasoningEffort: true,
            supportsToolCalling: true,
            supportsVision: false,
            isFamilyDefault: false,
            blurb: "Coding-tuned OpenAI model for long-horizon edits."
        ),
        CloudModelEntry(
            id: "gpt-5.1",
            displayName: "GPT-5.1",
            family: "GPT-5",
            providerID: ModelDefaults.openAIProviderID,
            contextWindow: 400_000,
            supportsReasoningEffort: true,
            supportsToolCalling: true,
            supportsVision: true,
            isFamilyDefault: false,
            blurb: "Older OpenAI reasoning model."
        ),
        CloudModelEntry(
            id: ModelDefaults.openAIFastModelID,
            displayName: "GPT-5 mini",
            family: "GPT-5",
            providerID: ModelDefaults.openAIProviderID,
            contextWindow: 400_000,
            supportsReasoningEffort: true,
            supportsToolCalling: true,
            supportsVision: true,
            isFamilyDefault: false,
            blurb: "Cost-efficient OpenAI model for well-defined tasks."
        ),
        CloudModelEntry(
            id: ModelDefaults.openAIUtilityModelID,
            displayName: "GPT-5 nano",
            family: "GPT-5",
            providerID: ModelDefaults.openAIProviderID,
            contextWindow: 400_000,
            supportsReasoningEffort: true,
            supportsToolCalling: true,
            supportsVision: true,
            isFamilyDefault: false,
            blurb: "Fastest OpenAI GPT-5 tier."
        ),
    ]

    public static let openRouter: [CloudModelEntry] = [
        CloudModelEntry(
            id: "openrouter-openai-gpt-5.5",
            routeModelID: ModelDefaults.openRouterModelID,
            displayName: "GPT-5.5 via OpenRouter",
            family: "GPT-5",
            providerID: ModelDefaults.openRouterProviderID,
            contextWindow: 400_000,
            supportsReasoningEffort: true,
            supportsToolCalling: true,
            supportsVision: true,
            isFamilyDefault: true,
            blurb: "OpenRouter route for the default OpenAI cloud model."
        ),
        CloudModelEntry(
            id: "openrouter-openai-gpt-5.2-codex",
            routeModelID: ModelDefaults.openRouterCodingModelID,
            displayName: "GPT-5.2 Codex via OpenRouter",
            family: "GPT-5",
            providerID: ModelDefaults.openRouterProviderID,
            contextWindow: 400_000,
            supportsReasoningEffort: true,
            supportsToolCalling: true,
            supportsVision: false,
            isFamilyDefault: false,
            blurb: "OpenRouter route for coding-heavy work."
        ),
        CloudModelEntry(
            id: "openrouter-openai-gpt-5-mini",
            routeModelID: ModelDefaults.openRouterFastModelID,
            displayName: "GPT-5 mini via OpenRouter",
            family: "GPT-5",
            providerID: ModelDefaults.openRouterProviderID,
            contextWindow: 400_000,
            supportsReasoningEffort: true,
            supportsToolCalling: true,
            supportsVision: true,
            isFamilyDefault: false,
            blurb: "OpenRouter route for cost-efficient utility work."
        ),
        CloudModelEntry(
            id: "openrouter-openai-gpt-5-nano",
            routeModelID: ModelDefaults.openRouterUtilityModelID,
            displayName: "GPT-5 nano via OpenRouter",
            family: "GPT-5",
            providerID: ModelDefaults.openRouterProviderID,
            contextWindow: 400_000,
            supportsReasoningEffort: true,
            supportsToolCalling: true,
            supportsVision: true,
            isFamilyDefault: false,
            blurb: "OpenRouter route for fastest hosted utility work."
        ),
    ]

    public static let elizaCloud: [CloudModelEntry] = [
        CloudModelEntry(
            id: "eliza-cloud-auto",
            routeModelID: ModelDefaults.elizaCloudModelID,
            displayName: "Eliza Cloud Auto",
            family: "Eliza Cloud",
            providerID: ModelDefaults.elizaCloudProviderID,
            contextWindow: 0,
            supportsReasoningEffort: false,
            supportsToolCalling: true,
            supportsVision: false,
            isFamilyDefault: true,
            blurb: "Lets Eliza Cloud select the hosted model."
        ),
    ]

    public static var all: [CloudModelEntry] {
        router + codex + openAI + openRouter + elizaCloud
    }

    public static func entry(for id: String) -> CloudModelEntry? {
        all.first { $0.id == id }
    }

    public static func models(provider: String) -> [CloudModelEntry] {
        all.filter { $0.providerID == provider }
    }

    public static func defaultModel(provider: String) -> CloudModelEntry? {
        let providerModels = models(provider: provider)
        return providerModels.first(where: { $0.isFamilyDefault }) ?? providerModels.first
    }
}
