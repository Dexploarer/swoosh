// DetourPersonalizationCodexConnectors.swift — Codex connector setup candidates (0.5A)

import Foundation

@MainActor
extension DetourPersonalizationRunner {
    func addCodexConnectorCandidates(to candidates: inout [DetourSetupCandidate]) {
        let catalog = DetourCodexConnectorCatalog.load()
        for item in catalog.items {
            guard item.toolCount > 0 else { continue }
            let id = codexConnectorCandidateID(item.displayName)
            candidates.append(candidate(
                id: id,
                category: .connector,
                title: codexConnectorTitle(item.displayName),
                detail: codexConnectorDetail(item),
                source: "Codex connector catalog",
                recommended: true,
                prompt: "Use \(item.displayName) with Detour?",
                credentialKeys: codexConnectorCredentialKeys(id),
                scope: codexConnectorScope(id)
            ))
        }
    }

    private func codexConnectorCandidateID(_ displayName: String) -> String {
        switch displayName.lowercased() {
        case "github":
            return "connector.github"
        case "linear":
            return "connector.linear"
        case "notion", "notion (legacy)":
            return "connector.notion"
        case "openai platform":
            return "connector.openai-platform"
        case "google drive":
            return "connector.google-drive"
        case "hugging face":
            return "connector.hugging-face"
        case "adobe photoshop":
            return "connector.adobe-photoshop"
        case "ace knowledge graph":
            return "connector.ace-knowledge-graph"
        default:
            return "connector.\(DetourCodexConnectorCatalog.slug(displayName))"
        }
    }

    private func codexConnectorTitle(_ displayName: String) -> String {
        displayName.replacingOccurrences(of: " (Legacy)", with: "")
    }

    private func codexConnectorDetail(_ item: DetourCodexConnectorCatalogItem) -> String {
        let writeCount = item.actionToolCount
        if writeCount > 0 {
            return "\(item.toolCount) Codex tools, including \(writeCount) action tools"
        }
        return "\(item.toolCount) Codex read tools"
    }

    private func codexConnectorCredentialKeys(_ candidateID: String) -> [String]? {
        switch candidateID {
        case "connector.github":
            return ["GITHUB_TOKEN", "GITHUB_USER_PAT", "GITHUB_AGENT_PAT"]
        case "connector.linear":
            return ["LINEAR_API_KEY", "LINEAR_ACCESS_TOKEN"]
        case "connector.notion":
            return ["NOTION_TOKEN", "NOTION_API_KEY"]
        case "connector.openai-platform":
            return ["OPENAI_API_KEY", "CODEX_AUTH_TOKEN"]
        case "connector.hugging-face":
            return ["HF_TOKEN", "HUGGINGFACE_TOKEN"]
        case "connector.vercel":
            return ["VERCEL_TOKEN"]
        default:
            return nil
        }
    }

    private func codexConnectorScope(_ candidateID: String) -> DetourDelegationRole {
        switch candidateID {
        case "connector.openai-platform", "connector.binance":
            return .agent
        default:
            return .user
        }
    }
}
