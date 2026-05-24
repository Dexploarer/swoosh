// SwooshUI/DashboardPanes/DashboardPaneDisplayLogic.swift — Pure dashboard pane display helpers — 0.9U

#if os(macOS)

import Foundation
import SwooshClient
import SwooshModels

enum DashboardProviderOrdering {
    static let priorityIDs = [
        ModelDefaults.codexProviderID,
        ModelDefaults.openAIProviderID,
        ModelDefaults.openRouterProviderID,
        ModelDefaults.localFoundationProviderID,
        ModelDefaults.localMLXProviderID,
        ModelDefaults.localOpenAIProviderID,
        "local-diagnostic"
    ]

    static func orderedIDs(_ ids: [String]) -> [String] {
        ids.enumerated()
            .sorted { lhs, rhs in
                let lhsRank = rank(providerID: lhs.element)
                let rhsRank = rank(providerID: rhs.element)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    static func orderedProviders(_ providers: [ProviderSummary]) -> [ProviderSummary] {
        let orderedIDs = orderedIDs(providers.map(\.id))
        return orderedIDs.compactMap { id in providers.first { $0.id == id } }
    }

    private static func rank(providerID: String) -> Int {
        priorityIDs.firstIndex(of: providerID) ?? priorityIDs.count
    }
}

enum DashboardProviderDisplay {
    static func acceptsAPIKey(providerID: String) -> Bool {
        [ModelDefaults.openAIProviderID, ModelDefaults.openRouterProviderID].contains(providerID)
    }

    static func blurb(providerID: String) -> String {
        switch providerID {
        case ModelDefaults.codexProviderID:
            return "Uses your ChatGPT Plus / Pro subscription via the local Codex CLI. No API key."
        case ModelDefaults.openAIProviderID:
            return "Direct OpenAI Platform API. Paste sk-… to enable GPT-5.x."
        case ModelDefaults.openRouterProviderID:
            return "Routed access to many model providers under one API."
        case ModelDefaults.localFoundationProviderID:
            return "Apple's on-device Foundation Models. Free, private."
        case ModelDefaults.localMLXProviderID:
            return "MLX Swift inference on Apple Silicon with Gemma 4/Qwen hub models."
        case ModelDefaults.localOpenAIProviderID:
            return "Local OpenAI-compatible servers like Ollama or LM Studio."
        case "local-diagnostic":
            return "Deterministic fallback used when no provider is configured."
        default:
            return "External provider."
        }
    }

    static func costLabel(providerID: String) -> String {
        switch providerID {
        case ModelDefaults.codexProviderID:
            return "ChatGPT Plus"
        case ModelDefaults.openAIProviderID, ModelDefaults.openRouterProviderID:
            return "Paid"
        case ModelDefaults.localFoundationProviderID, ModelDefaults.localMLXProviderID, ModelDefaults.localOpenAIProviderID:
            return "Free"
        default:
            return "—"
        }
    }

    static func locationLabel(providerID: String) -> String {
        switch providerID {
        case ModelDefaults.codexProviderID, ModelDefaults.openAIProviderID, ModelDefaults.openRouterProviderID:
            return "Cloud"
        default:
            return "Local"
        }
    }

    static func statusLabel(for status: String) -> String {
        switch status {
        case "signed_in":
            return "Signed in"
        case "configured":
            return "API key configured"
        case "missing_key":
            return "API key required"
        case "needs_signin":
            return "Sign in to ChatGPT"
        case "running":
            return "Running"
        case "available":
            return "Available"
        case "not_running":
            return "Not running"
        case "active_until_model_provider_configured":
            return "Fallback (diagnostic)"
        default:
            return status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

enum LocalModelDisplayFormatter {
    static func installedSubtitle(
        family: String?,
        parameterSize: String?,
        quantization: String?,
        isChatCapable: Bool
    ) -> String {
        let parts: [String?] = [
            family.map { "Family: \($0)" },
            parameterSize,
            quantization,
            isChatCapable ? nil : "Embedding-only (not chat-capable)"
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    static func formattedDownloadCount(_ n: Int) -> String {
        switch n {
        case 1_000_000...:
            return "\(n / 1_000_000)M ↓"
        case 1_000...:
            return "\(n / 1_000)k ↓"
        default:
            return "\(n) ↓"
        }
    }

    static func formattedSize(_ bytes: Int64?) -> String? {
        guard let bytes else { return nil }
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        return String(format: "%.0f MB", Double(bytes) / 1_048_576)
    }
}

#endif
