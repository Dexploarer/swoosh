// DetourPersonalizationCandidateBuilder.swift — personalization setup services (0.5A)

import Foundation

@MainActor
extension DetourPersonalizationRunner {
    func setupCandidates(
        installedApps: Set<String>,
        appUsage: AppUsageInventory,
        git: GitActivityInventory,
        contacts: ContactInventory,
        messages: MessageInventory,
        auth: AuthInventory
    ) -> [DetourSetupCandidate] {
        var candidates: [DetourSetupCandidate] = []
        addConnectorCandidates(installedApps: installedApps, auth: auth, messages: messages, to: &candidates)
        addCodexConnectorCandidates(to: &candidates)
        addOpenHumanIntegrationCandidates(installedApps: installedApps, auth: auth, to: &candidates)
        addAddonCandidates(auth: auth, to: &candidates)
        addMCPServerCandidates(installedApps: installedApps, auth: auth, to: &candidates)
        addCredentialCandidates(auth: auth, to: &candidates)
        addModelCandidates(auth: auth, to: &candidates)
        addContextCandidates(appUsage: appUsage, git: git, contacts: contacts, messages: messages, auth: auth, to: &candidates)
        return candidates.uniquedByID()
    }

    func addCredentialCandidates(auth: AuthInventory, to candidates: inout [DetourSetupCandidate]) {
        for finding in auth.credentialFindings {
            let scopeText = finding.scope == .agent ? "agent" : "user"
            candidates.append(candidate(
                id: finding.id,
                category: .account,
                title: finding.title,
                detail: finding.detail,
                source: finding.source,
                recommended: true,
                prompt: "Detour found \(finding.title). Use it as \(scopeText)?",
                foundCount: finding.count,
                credentialProviderID: finding.providerID,
                credentialKeys: finding.keys,
                scope: finding.scope
            ))
        }
    }

    func addAddonCandidates(auth: AuthInventory, to candidates: inout [DetourSetupCandidate]) {
        let hasAgentMailKey = auth.hasAny(["AGENTMAIL_API_KEY"])
        candidates.append(candidate(
            id: "connector.agentmail",
            category: .connector,
            title: "AgentMail",
            detail: hasAgentMailKey
                ? "AgentMail access was found. Detour can set up an agent-owned email inbox."
                : "Give the agent its own email inbox. Needs an AgentMail API key or agent sign-up with email verification.",
            source: "agent identity add-on",
            recommended: true,
            prompt: "Use AgentMail for the agent's own email?",
            credentialKeys: ["AGENTMAIL_API_KEY"],
            scope: .agent
        ))
        candidates.append(candidate(
            id: "skill.agentmail",
            category: .skill,
            title: "AgentMail skill",
            detail: "Adds email workflow knowledge for inboxes, messages, threads, drafts, and replies.",
            source: "official AgentMail skill",
            recommended: true
        ))
    }

    func addMCPServerCandidates(
        installedApps: Set<String>,
        auth: AuthInventory,
        to candidates: inout [DetourSetupCandidate]
    ) {
        candidates.append(candidate(
            id: "mcp.agentmail",
            category: .mcp,
            title: "AgentMail MCP server",
            detail: auth.hasAny(["AGENTMAIL_API_KEY"])
                ? "AgentMail can be added as tools for the agent inbox."
                : "Adds AgentMail tools for the agent inbox. Needs an AgentMail API key.",
            source: "AgentMail MCP",
            recommended: true,
            credentialKeys: ["AGENTMAIL_API_KEY"],
            scope: .agent
        ))
        if hasGitHubSignals(installedApps: installedApps, auth: auth) {
            candidates.append(candidate(
                id: "mcp.github",
                category: .mcp,
                title: "GitHub MCP server",
                detail: auth.hasAny(["GITHUB_TOKEN", "GITHUB_USER_PAT"])
                    ? "GitHub can be added as approval-gated repo, issue, and PR tools."
                    : "Adds GitHub repo, issue, and PR tools. Needs a GitHub token.",
                source: "developer activity",
                recommended: true,
                credentialKeys: ["GITHUB_TOKEN", "GITHUB_USER_PAT"],
                scope: .user
            ))
        }
        if containsAny(["slack"], in: installedApps) || auth.hasAny(["SLACK_BOT_TOKEN", "SLACK_API_TOKEN"]) {
            candidates.append(candidate(
                id: "mcp.slack",
                category: .mcp,
                title: "Slack MCP server",
                detail: auth.hasAny(["SLACK_BOT_TOKEN", "SLACK_API_TOKEN"])
                    ? "Slack can be added as approval-gated workspace tools."
                    : "Adds Slack workspace tools. Needs a Slack bot token and team ID.",
                source: "installed app",
                recommended: true,
                credentialKeys: ["SLACK_BOT_TOKEN", "SLACK_API_TOKEN", "SLACK_TEAM_ID", "SLACK_CHANNEL_IDS"],
                scope: .agent
            ))
        }
        if containsAny(["notion"], in: installedApps) || auth.hasAny(["NOTION_TOKEN", "NOTION_API_KEY"]) {
            candidates.append(candidate(
                id: "mcp.notion",
                category: .mcp,
                title: "Notion MCP server",
                detail: auth.hasAny(["NOTION_TOKEN", "NOTION_API_KEY"])
                    ? "Notion can be added as approval-gated workspace tools."
                    : "Adds Notion workspace tools. Needs a Notion integration token.",
                source: "installed app",
                recommended: true,
                credentialKeys: ["NOTION_TOKEN", "NOTION_API_KEY"],
                scope: .user
            ))
        }
        if containsAny(["linear"], in: installedApps) || auth.hasAny(["LINEAR_API_KEY", "LINEAR_ACCESS_TOKEN"]) {
            candidates.append(candidate(
                id: "mcp.linear",
                category: .mcp,
                title: "Linear MCP server",
                detail: auth.hasAny(["LINEAR_API_KEY", "LINEAR_ACCESS_TOKEN"])
                    ? "Linear can be added as approval-gated issue and project tools."
                    : "Adds Linear issue and project tools. Needs a Linear API key.",
                source: "installed app",
                recommended: true,
                credentialKeys: ["LINEAR_API_KEY", "LINEAR_ACCESS_TOKEN"],
                scope: .user
            ))
        }
    }

    func addConnectorCandidates(
        installedApps: Set<String>,
        auth: AuthInventory,
        messages: MessageInventory,
        to candidates: inout [DetourSetupCandidate]
    ) {
        if containsAny(["discord"], in: installedApps) {
            candidates.append(candidate(
                id: "connector.discord",
                category: .connector,
                title: "Discord",
                detail: auth.hasAny(["DISCORD_API_TOKEN", "DISCORD_BOT_TOKEN"])
                    ? "Discord is installed and a credential was found"
                    : "Discord is installed but needs a credential",
                source: "installed app",
                recommended: true,
                credentialKeys: ["DISCORD_BOT_TOKEN"],
                scope: .agent
            ))
        }
        if containsAny(["telegram"], in: installedApps) {
            candidates.append(candidate(
                id: "connector.telegram",
                category: .connector,
                title: "Telegram",
                detail: auth.hasAny(["TELEGRAM_BOT_TOKEN"])
                    ? "Telegram is installed and a bot credential was found"
                    : "Telegram is installed but needs a bot credential",
                source: "installed app",
                recommended: true,
                credentialKeys: ["TELEGRAM_BOT_TOKEN"],
                scope: .agent
            ))
        }
        candidates.append(candidate(
            id: "connector.imessage",
            category: .connector,
            title: "iMessage",
            detail: messages.chatDatabaseStatus,
            source: "macOS Messages",
            recommended: true
        ))
        if hasGitHubSignals(installedApps: installedApps, auth: auth) {
            candidates.append(candidate(
                id: "connector.github",
                category: .connector,
                title: "GitHub",
                detail: auth.hasAny(["GITHUB_USER_PAT", "GITHUB_AGENT_PAT", "GITHUB_TOKEN"])
                    ? "GitHub account access was found"
                    : "GitHub activity was found but needs account access",
                source: "developer activity",
                recommended: true,
                credentialKeys: ["GITHUB_USER_PAT"],
                scope: .user
            ))
        }
        if containsAny(["slack"], in: installedApps) {
            candidates.append(candidate(
                id: "connector.slack",
                category: .connector,
                title: "Slack",
                detail: "Slack is installed but needs account access",
                source: "installed app",
                recommended: true,
                credentialKeys: ["SLACK_BOT_TOKEN", "SLACK_TEAM_ID"],
                scope: .agent
            ))
        }
        if containsAny(["notion"], in: installedApps) {
            candidates.append(candidate(
                id: "connector.notion",
                category: .connector,
                title: "Notion",
                detail: "Notion is installed but needs account access",
                source: "installed app",
                recommended: true,
                credentialKeys: ["NOTION_TOKEN"],
                scope: .user
            ))
        }
        if containsAny(["linear"], in: installedApps) {
            candidates.append(candidate(
                id: "connector.linear",
                category: .connector,
                title: "Linear",
                detail: "Linear is installed but needs account access",
                source: "installed app",
                recommended: true,
                credentialKeys: ["LINEAR_API_KEY"],
                scope: .user
            ))
        }
        if hasBrowser(installedApps) {
            candidates.append(candidate(
                id: "connector.x",
                category: .connector,
                title: "X",
                detail: auth.xCookieStatus,
                source: "browser auth",
                recommended: auth.browserCookieStoresFound
            ))
        }
    }

    func addModelCandidates(auth: AuthInventory, to candidates: inout [DetourSetupCandidate]) {
        let providers = [
            ("openai", "OpenAI", "OPENAI_API_KEY"),
            ("openrouter", "OpenRouter", "OPENROUTER_API_KEY"),
            ("eliza-cloud", "Eliza Cloud", "ELIZA_CLOUD_API_KEY"),
            ("anthropic", "Claude", "ANTHROPIC_API_KEY"),
            ("gemini", "Gemini", "GEMINI_API_KEY"),
            ("codex", "Codex", "CODEX_AUTH_TOKEN"),
        ]
        for (id, title, key) in providers {
            candidates.append(candidate(
                id: "model.\(id)",
                category: .model,
                title: title,
                detail: auth.importedProviders.contains(id) || auth.hasAny([key])
                    ? "\(title) access was found"
                    : "\(title) needs a key",
                source: "local auth",
                recommended: auth.importedProviders.contains(id) || auth.hasAny([key]),
                credentialKeys: [key],
                scope: .agent
            ))
        }
        candidates.append(candidate(
            id: "model.local.omnivoice",
            category: .model,
            title: "OmniVoice local",
            detail: "local voice is ready on this Mac",
            source: "bundled runtime",
            recommended: true
        ))
    }

    func addContextCandidates(
        appUsage: AppUsageInventory,
        git: GitActivityInventory,
        contacts: ContactInventory,
        messages: MessageInventory,
        auth: AuthInventory,
        to candidates: inout [DetourSetupCandidate]
    ) {
        candidates.append(candidate(
            id: "context.app-usage",
            category: .context,
            title: "App usage",
            detail: appUsage.summary,
            source: "~/.swoosh/app-usage.jsonl",
            recommended: appUsage.requested && !appUsage.topApps.isEmpty
        ))
        candidates.append(candidate(
            id: "context.git-history",
            category: .context,
            title: "Git history",
            detail: git.summary,
            source: "local repos",
            recommended: git.requested && !git.repositories.isEmpty
        ))
        if !contacts.authorized {
            candidates.append(candidate(
                id: "context.contacts",
                category: .permission,
                title: "Contacts",
                detail: contacts.summary,
                source: "Contacts",
                recommended: false
            ))
        }
        if auth.legacy.vaultFound {
            candidates.append(candidate(
                id: "context.legacy-detour-vault",
                category: .permission,
                title: "Legacy Detour vault",
                detail: auth.legacyVaultDetail,
                source: "~/.eliza/vault.json",
                recommended: auth.legacy.decrypted && !auth.legacy.availableKeys.isEmpty
            ))
        }
        if contacts.totalCount > 0 || !messages.relationships.isEmpty {
            candidates.append(candidate(
                id: "context.relationships",
                category: .context,
                title: "Relationship map",
                detail: "\(contacts.totalCount) contacts, \(messages.relationships.count) message handles",
                source: "Contacts and Messages",
                recommended: contacts.authorized || !messages.relationships.isEmpty
            ))
        }
    }

}
