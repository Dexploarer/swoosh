// SwooshModels/CloudCatalog.swift — 0.9Q Cloud model catalog (OpenAI, etc.)
//
// Cloud models are typed separately from CuratedCatalog because:
//   • No hardware tier / format / install command — they live in the provider.
//   • They carry pricing, context window, reasoning support, and provider routing.
//   • The UI picker (see SwooshUI/Pickers/ModelPicker.swift) consumes this list
//     to render the model menu shown in the Codex-style screenshot.
//
// The OpenAI lineup mirrors what ChatGPT plan OAuth grants Codex CLI users
// today (May 2026): GPT-5.5 (default), GPT-5.4, GPT-5.4-Mini, GPT-5.3-Codex,
// GPT-5.2. These are reachable to Swoosh via Platform API keys (api.openai.com)
// — NOT via the user's ChatGPT plan OAuth, which is first-party-only.

import Foundation

// MARK: - Cloud model entry

/// A cloud-hosted model. Provider-routed, not locally installable.
public struct CloudModelEntry: Codable, Sendable, Identifiable, Hashable {
    /// Provider-recognized model ID, e.g. `"gpt-5.5"`, `"claude-sonnet-4-6"`.
    public let id: String

    /// Display name, e.g. `"GPT-5.5"`.
    public let displayName: String

    /// Family for grouping, e.g. `"GPT-5"`.
    public let family: String

    /// Provider that serves this model, e.g. `"openai"`, `"openrouter"`.
    public let providerID: String

    /// Max context window in tokens.
    public let contextWindow: Int

    /// Whether the model exposes a `reasoning_effort` knob.
    public let supportsReasoningEffort: Bool

    /// Whether the model accepts tool/function calls.
    public let supportsToolCalling: Bool

    /// Whether the model accepts image input.
    public let supportsVision: Bool

    /// Whether this is the family's recommended default in pickers.
    public let isFamilyDefault: Bool

    /// Short one-line description shown in the picker subtitle slot.
    public let blurb: String

    public init(
        id: String,
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

// MARK: - Catalog

public enum CloudCatalog {

    /// Models reachable through Swoosh's OpenAI provider against api.openai.com.
    /// Mirrors the Codex CLI / ChatGPT-plan picker lineup as of May 2026.
    public static let openAI: [CloudModelEntry] = [
        CloudModelEntry(
            id: "gpt-5.5",
            displayName: "GPT-5.5",
            family: "GPT-5",
            providerID: "openai",
            contextWindow: 400_000,
            supportsReasoningEffort: true,
            supportsToolCalling: true,
            supportsVision: true,
            isFamilyDefault: true,
            blurb: "Latest flagship. Best for agentic coding."
        ),
        CloudModelEntry(
            id: "gpt-5.4",
            displayName: "GPT-5.4",
            family: "GPT-5",
            providerID: "openai",
            contextWindow: 400_000,
            supportsReasoningEffort: true,
            supportsToolCalling: true,
            supportsVision: true,
            isFamilyDefault: false,
            blurb: "Previous-generation flagship."
        ),
        CloudModelEntry(
            id: "gpt-5.4-mini",
            displayName: "GPT-5.4-Mini",
            family: "GPT-5",
            providerID: "openai",
            contextWindow: 200_000,
            supportsReasoningEffort: true,
            supportsToolCalling: true,
            supportsVision: true,
            isFamilyDefault: false,
            blurb: "Cost-efficient tier. CI and high-volume."
        ),
        CloudModelEntry(
            id: "gpt-5.3-codex",
            displayName: "GPT-5.3-Codex",
            family: "GPT-5",
            providerID: "openai",
            contextWindow: 400_000,
            supportsReasoningEffort: true,
            supportsToolCalling: true,
            supportsVision: false,
            isFamilyDefault: false,
            blurb: "Coding-tuned. Stronger on edits and patches."
        ),
        CloudModelEntry(
            id: "gpt-5.2",
            displayName: "GPT-5.2",
            family: "GPT-5",
            providerID: "openai",
            contextWindow: 400_000,
            supportsReasoningEffort: true,
            supportsToolCalling: true,
            supportsVision: true,
            isFamilyDefault: false,
            blurb: "Long-context generalist."
        ),
    ]

    // MARK: - Anthropic

    public static let anthropic: [CloudModelEntry] = [
        CloudModelEntry(
            id: "claude-opus-4-7",
            displayName: "Claude Opus 4.7",
            family: "Claude 4",
            providerID: "anthropic",
            contextWindow: 1_000_000,
            supportsReasoningEffort: false,
            supportsToolCalling: true,
            supportsVision: true,
            isFamilyDefault: true,
            blurb: "Anthropic's flagship. 1M context, strongest reasoning."
        ),
        CloudModelEntry(
            id: "claude-sonnet-4-6",
            displayName: "Claude Sonnet 4.6",
            family: "Claude 4",
            providerID: "anthropic",
            contextWindow: 500_000,
            supportsReasoningEffort: false,
            supportsToolCalling: true,
            supportsVision: true,
            isFamilyDefault: false,
            blurb: "Workhorse — fast, capable, lower cost than Opus."
        ),
        CloudModelEntry(
            id: "claude-haiku-4-5",
            displayName: "Claude Haiku 4.5",
            family: "Claude 4",
            providerID: "anthropic",
            contextWindow: 200_000,
            supportsReasoningEffort: false,
            supportsToolCalling: true,
            supportsVision: true,
            isFamilyDefault: false,
            blurb: "Fastest + cheapest Claude. Good for high-volume."
        ),
    ]

    // MARK: - Google

    public static let google: [CloudModelEntry] = [
        CloudModelEntry(
            id: "gemini-3.0",
            displayName: "Gemini 3.0",
            family: "Gemini 3",
            providerID: "google",
            contextWindow: 2_000_000,
            supportsReasoningEffort: false,
            supportsToolCalling: true,
            supportsVision: true,
            isFamilyDefault: true,
            blurb: "Google flagship — 2M-token context, multimodal."
        ),
        CloudModelEntry(
            id: "gemini-2.5-pro",
            displayName: "Gemini 2.5 Pro",
            family: "Gemini 2.5",
            providerID: "google",
            contextWindow: 1_000_000,
            supportsReasoningEffort: false,
            supportsToolCalling: true,
            supportsVision: true,
            isFamilyDefault: false,
            blurb: "Long-context reasoning workhorse."
        ),
        CloudModelEntry(
            id: "gemini-2.5-flash",
            displayName: "Gemini 2.5 Flash",
            family: "Gemini 2.5",
            providerID: "google",
            contextWindow: 1_000_000,
            supportsReasoningEffort: false,
            supportsToolCalling: true,
            supportsVision: true,
            isFamilyDefault: false,
            blurb: "Fast + cheap. Tool-calling preserved."
        ),
    ]

    // MARK: - xAI

    public static let xai: [CloudModelEntry] = [
        CloudModelEntry(
            id: "grok-4-2",
            displayName: "Grok 4.2",
            family: "Grok 4",
            providerID: "xai",
            contextWindow: 256_000,
            supportsReasoningEffort: false,
            supportsToolCalling: true,
            supportsVision: true,
            isFamilyDefault: true,
            blurb: "xAI flagship. Realtime search + reasoning."
        ),
        CloudModelEntry(
            id: "grok-4-1",
            displayName: "Grok 4.1",
            family: "Grok 4",
            providerID: "xai",
            contextWindow: 128_000,
            supportsReasoningEffort: false,
            supportsToolCalling: true,
            supportsVision: true,
            isFamilyDefault: false,
            blurb: "Previous Grok flagship."
        ),
    ]

    // MARK: - DeepSeek

    public static let deepseek: [CloudModelEntry] = [
        CloudModelEntry(
            id: "deepseek-v4-pro",
            displayName: "DeepSeek V4 Pro",
            family: "DeepSeek V4",
            providerID: "deepseek",
            contextWindow: 128_000,
            supportsReasoningEffort: true,
            supportsToolCalling: true,
            supportsVision: false,
            isFamilyDefault: true,
            blurb: "Expert Mode — deeper reasoning, slower."
        ),
        CloudModelEntry(
            id: "deepseek-v4-flash",
            displayName: "DeepSeek V4 Flash",
            family: "DeepSeek V4",
            providerID: "deepseek",
            contextWindow: 128_000,
            supportsReasoningEffort: false,
            supportsToolCalling: true,
            supportsVision: false,
            isFamilyDefault: false,
            blurb: "Instant Mode — sub-second responses."
        ),
    ]

    // MARK: - Mistral

    public static let mistral: [CloudModelEntry] = [
        CloudModelEntry(
            id: "mistral-large-2",
            displayName: "Mistral Large 2",
            family: "Mistral",
            providerID: "mistral",
            contextWindow: 128_000,
            supportsReasoningEffort: false,
            supportsToolCalling: true,
            supportsVision: false,
            isFamilyDefault: true,
            blurb: "Mistral's flagship. Strong on European languages."
        ),
        CloudModelEntry(
            id: "codestral-2",
            displayName: "Codestral 2",
            family: "Mistral",
            providerID: "mistral",
            contextWindow: 256_000,
            supportsReasoningEffort: false,
            supportsToolCalling: true,
            supportsVision: false,
            isFamilyDefault: false,
            blurb: "Code-tuned variant. Cheaper for code tasks."
        ),
    ]

    // MARK: - Meta (via OpenRouter / Together)

    public static let meta: [CloudModelEntry] = [
        CloudModelEntry(
            id: "llama-4-405b",
            displayName: "Llama 4 405B",
            family: "Llama 4",
            providerID: "meta",
            contextWindow: 128_000,
            supportsReasoningEffort: false,
            supportsToolCalling: true,
            supportsVision: true,
            isFamilyDefault: true,
            blurb: "Open-weights flagship. Routed through OpenRouter."
        ),
    ]

    /// The full set across every wired provider. Pickers default to this so
    /// the user sees what's available from each provider in one place.
    public static var all: [CloudModelEntry] {
        openAI + anthropic + google + xai + deepseek + mistral + meta
    }

    /// Human-readable name for a `providerID` field. Used by the picker to
    /// group entries under their parent provider in the sheet.
    public static func providerDisplayName(_ providerID: String) -> String {
        switch providerID {
        case "openai":     return "OpenAI"
        case "anthropic":  return "Anthropic"
        case "google":     return "Google"
        case "xai":        return "xAI"
        case "deepseek":   return "DeepSeek"
        case "mistral":    return "Mistral"
        case "meta":       return "Meta"
        case "openrouter": return "OpenRouter"
        default:           return providerID.capitalized
        }
    }

    /// Lookup by id. Returns nil if the id is not in the catalog.
    public static func entry(for id: String) -> CloudModelEntry? {
        all.first { $0.id == id }
    }

    /// All models for a given provider.
    public static func models(provider: String) -> [CloudModelEntry] {
        all.filter { $0.providerID == provider }
    }

    /// The family-default for a provider — what a picker should select by
    /// default if the user has no saved preference.
    public static func defaultModel(provider: String) -> CloudModelEntry? {
        let providerModels = models(provider: provider)
        return providerModels.first(where: { $0.isFamilyDefault }) ?? providerModels.first
    }
}
