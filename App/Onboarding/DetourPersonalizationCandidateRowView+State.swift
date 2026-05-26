// DetourPersonalizationCandidateRowView+State.swift — Detour onboarding view slice (0.5A)

import AppKit
import QuartzCore

extension DetourPersonalizationCandidateRowView {
    func configureButton(_ button: NSButton, action: Selector) {
        button.target = self
        button.action = action
        button.isBordered = false
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.contentTintColor = .white
        button.refusesFirstResponder = true
        button.focusRingType = .none
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
    }

    func updateVisualState() {
        statusField.stringValue = statusText
        statusField.layer?.backgroundColor = (approved
            ? NSColor.systemGreen.withAlphaComponent(0.42)
            : NSColor.white.withAlphaComponent(0.16)).cgColor
        statusField.textColor = approved ? .white : NSColor.white.withAlphaComponent(0.74)
        applyButton.title = approved ? "Using" : "Use"
        skipButton.title = approved ? "Remove" : "Not using"
        layer?.backgroundColor = (approved ? NSColor.systemGreen.withAlphaComponent(0.12) : NSColor.black.withAlphaComponent(0.12)).cgColor
        layer?.borderColor = (approved ? NSColor.systemGreen.withAlphaComponent(0.42) : NSColor.white.withAlphaComponent(0.16)).cgColor
        updateButton(applyButton, active: approved, activeColor: NSColor.systemGreen.withAlphaComponent(0.46))
        updateButton(skipButton, active: !approved, activeColor: NSColor.white.withAlphaComponent(0.24))
        updateButton(permissionButton, active: supportsPermissionButton, activeColor: NSColor.systemBlue.withAlphaComponent(0.48))
        updateButton(userButton, active: scope == .user, activeColor: NSColor.systemOrange.withAlphaComponent(0.48))
        updateButton(agentButton, active: scope == .agent, activeColor: NSColor.systemBlue.withAlphaComponent(0.48))
    }

    func updateButton(_ button: NSButton, active: Bool, activeColor: NSColor) {
        button.alphaValue = active ? 1 : 0.74
        button.layer?.backgroundColor = (active ? activeColor : NSColor.white.withAlphaComponent(0.12)).cgColor
        button.layer?.borderColor = NSColor.white.withAlphaComponent(active ? 0.3 : 0.1).cgColor
        button.layer?.borderWidth = 1
    }

    var supportsScopeControls: Bool {
        candidate.scope != nil
            || candidate.prompt != nil
            || candidate.credentialProviderID != nil
            || candidate.credentialKeys?.isEmpty == false
            || candidate.id.hasPrefix("credential.")
    }

    var supportsPermissionButton: Bool {
        if candidate.id == "connector.agentmail" || candidate.id == "mcp.agentmail" { return true }
        return (candidate.id == "connector.imessage" || candidate.id == "context.messages")
            && candidate.detail.lowercased().contains("full disk access")
    }

    var setupActionTitle: String {
        candidate.id == "connector.agentmail" || candidate.id == "mcp.agentmail" ? "Configure" : "Grant Access"
    }

    var statusText: String {
        guard approved else { return "Not using" }
        guard supportsScopeControls else { return "Will set up" }
        switch scope {
        case .user:
            return "Will use as \(userDisplayName)"
        case .agent:
            return "Will use as \(agentDisplayName)"
        case nil:
            return "Choose owner"
        }
    }

    var ownerDescription: String? {
        guard supportsScopeControls else { return nil }
        switch scope {
        case .user:
            return "Belongs to \(userDisplayName). Detour can use it when acting as \(userDisplayName)."
        case .agent:
            return "Belongs to \(agentDisplayName). Detour can use it for agent-owned actions."
        case nil:
            return "Choose whether this belongs to you or to \(agentDisplayName)."
        }
    }

    var userDisplayName: String {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "you" : DetourSetupInsightRedaction.display(trimmed)
    }

    var agentDisplayName: String {
        let trimmed = agentName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Detour" : DetourSetupInsightRedaction.display(trimmed)
    }

    func rowTitle(_ candidate: DetourSetupCandidate) -> String {
        if let handle = xHandle(candidate) {
            return "X: @\(handle)"
        }
        if candidate.source == "Keychain",
           let provider = providerName(candidate) {
            return "\(provider) key"
        }
        return DetourSetupInsightRedaction.display(candidate.title)
    }

    func rowDetail(_ candidate: DetourSetupCandidate) -> String {
        let detail = [
            plainDescription(candidate),
            ownerDescription,
            duplicateDescription(candidate),
        ].compactMap(\.self).joined(separator: " ")
        return DetourSetupInsightRedaction.display(detail)
    }

    func plainDescription(_ candidate: DetourSetupCandidate) -> String {
        if let handle = xHandle(candidate) {
            let browser = browserName(candidate) ?? "the browser"
            if let owner = xAccountOwner(candidate) {
                return "Signed-in X account @\(handle) found in \(browser) for \(DetourSetupInsightRedaction.display(owner))."
            }
            return "Signed-in X account @\(handle) found in \(browser)."
        }
        if candidate.id.hasPrefix("credential.x.") {
            return candidate.detail
        }
        if candidate.source == "Keychain",
           let provider = providerName(candidate) {
            return "\(provider) credential found in Keychain."
        }
        if candidate.id.hasPrefix("credential.") {
            return "\(credentialLabel(candidate)) found."
        }
        if candidate.category == .connector {
            return connectorDescription(candidate)
        }
        if candidate.category == .mcp {
            return mcpDescription(candidate)
        }
        if candidate.id == "skill.agentmail" {
            return "Adds AgentMail workflows for email triage, drafts, replies, and inbox setup."
        }
        if candidate.category == .model {
            return modelDescription(candidate)
        }
        if candidate.id == "context.messages",
           candidate.detail.lowercased().contains("full disk access") {
            return "Messages were found. macOS may still ask for Full Disk Access."
        }
        if let count = candidate.foundCount {
            return "\(candidate.title) found \(count)."
        }
        return candidate.detail
    }

    func connectorDescription(_ candidate: DetourSetupCandidate) -> String {
        let text = candidateText(candidate)
        if text.contains("discord") {
            return text.contains("credential was found")
                ? "Discord is installed and a credential was found."
                : "Discord is installed. Detour can enable it when credentials are ready."
        }
        if text.contains("telegram") {
            return text.contains("bot credential was found")
                ? "Telegram is installed and a bot credential was found."
                : "Telegram is installed. Detour can enable it when credentials are ready."
        }
        if text.contains("imessage") {
            return "iMessage is available on this Mac."
        }
        if text.contains("agentmail") {
            return text.contains("access was found")
                ? "AgentMail access was found. Detour can give the agent its own email inbox."
                : "AgentMail gives the agent its own email inbox. It needs a key or sign-up before email is live."
        }
        if text.contains("github") {
            return "GitHub activity was found. Detour can connect it to issues, PRs, and repo context."
        }
        if text.contains("x") {
            return "X can be connected from the signed-in browser accounts you approve."
        }
        return "\(candidate.title) can be added to this setup."
    }

    func mcpDescription(_ candidate: DetourSetupCandidate) -> String {
        let text = candidateText(candidate)
        if text.contains("agentmail") {
            return "Adds AgentMail as tools for the agent inbox. Tool use stays approval-gated."
        }
        if text.contains("github") {
            return "Adds GitHub as tools for repos, issues, pull requests, and code search."
        }
        if text.contains("slack") {
            return "Adds Slack workspace tools for channels, messages, threads, reactions, and people."
        }
        if text.contains("notion") {
            return "Adds Notion workspace tools for pages, search, comments, and databases."
        }
        if text.contains("linear") {
            return "Adds Linear tools for issues, projects, and teams."
        }
        return "Adds \(candidate.title) as an MCP tool server. Tool use stays approval-gated."
    }

    func modelDescription(_ candidate: DetourSetupCandidate) -> String {
        let text = candidateText(candidate)
        if text.contains("needs api key") || text.contains("needs a key") {
            return "\(candidate.title) needs a key before Detour can use it."
        }
        if text.contains("omnivoice") {
            return "Local voice is ready on this Mac."
        }
        return "\(candidate.title) is ready for Detour to use."
    }

    func credentialLabel(_ candidate: DetourSetupCandidate) -> String {
        let text = candidateText(candidate)
        if text.contains("openai") { return "OpenAI model key" }
        if text.contains("openrouter") { return "OpenRouter model key" }
        if text.contains("eliza cloud") || text.contains("eliza-cloud") { return "Eliza Cloud key" }
        if text.contains("claude") || text.contains("anthropic") { return "Claude model key" }
        if text.contains("gemini") { return "Gemini model key" }
        if text.contains("agentmail") { return "AgentMail inbox key" }
        if text.contains("codex") { return "Codex login" }
        if text.contains("github") { return "GitHub account" }
        if text.contains("discord") { return "Discord account" }
        if text.contains("telegram") { return "Telegram bot account" }
        if text.contains("slack") { return "Slack workspace account" }
        if text.contains("notion") { return "Notion workspace account" }
        if text.contains("linear") { return "Linear workspace account" }
        return candidate.title
    }

    func duplicateDescription(_ candidate: DetourSetupCandidate) -> String? {
        if candidate.detail.lowercased().contains("stale duplicate") {
            return "Older duplicate entries were hidden."
        }
        guard let count = candidate.foundCount, count > 1 else { return nil }
        if candidate.id.hasPrefix("credential.x.") {
            return "Found in \(count) browser profiles."
        }
        return "\(count) matching records found."
    }

    func providerName(_ candidate: DetourSetupCandidate) -> String? {
        let text = candidateText(candidate)
        if text.contains("openai") { return "OpenAI" }
        if text.contains("openrouter") { return "OpenRouter" }
        if text.contains("eliza cloud") || text.contains("eliza-cloud") { return "Eliza Cloud" }
        if text.contains("claude") || text.contains("anthropic") { return "Claude" }
        if text.contains("gemini") { return "Gemini" }
        if text.contains("agentmail") { return "AgentMail" }
        if text.contains("codex") { return "Codex" }
        if text.contains("github") { return "GitHub" }
        if text.contains("discord") { return "Discord" }
        if text.contains("telegram") { return "Telegram" }
        if text.contains("slack") { return "Slack" }
        if text.contains("notion") { return "Notion" }
        if text.contains("linear") { return "Linear" }
        return nil
    }

    func xHandle(_ candidate: DetourSetupCandidate) -> String? {
        guard candidate.id.hasPrefix("credential.x.") || candidateText(candidate).contains("x session") else {
            return nil
        }
        for value in [candidate.title, candidate.detail] {
            if let handle = explicitXHandle(in: value) {
                return handle
            }
        }
        return nil
    }

    func explicitXHandle(in value: String) -> String? {
        var searchStart = value.startIndex
        while let marker = value[searchStart...].range(of: "@") {
            if marker.lowerBound > value.startIndex {
                let previous = value[value.index(before: marker.lowerBound)]
                if previous.isLetter || previous.isNumber || previous == "." || previous == "_" || previous == "-" {
                    searchStart = marker.upperBound
                    continue
                }
            }
            guard let handle = parsedXHandle(from: value[marker.upperBound...]) else {
                searchStart = marker.upperBound
                continue
            }
            let handleEnd = value.index(marker.upperBound, offsetBy: handle.count, limitedBy: value.endIndex) ?? value.endIndex
            if handleEnd < value.endIndex, value[handleEnd] == "." {
                searchStart = marker.upperBound
                continue
            }
            return handle
        }
        return nil
    }

    func parsedXHandle(from suffix: Substring) -> String? {
        var handle = ""
        for character in suffix {
            guard character.isLetter || character.isNumber || character == "_" else {
                break
            }
            handle.append(character)
        }
        return handle.isEmpty ? nil : handle
    }

    func xAccountOwner(_ candidate: DetourSetupCandidate) -> String? {
        for marker in ["Google account ", "signed in as "] {
            guard let range = candidate.detail.range(of: marker, options: [.caseInsensitive]) else {
                continue
            }
            let owner = candidate.detail[range.upperBound...]
                .split(separator: ";", maxSplits: 1)
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let owner, !owner.isEmpty {
                return owner
            }
        }
        return nil
    }

    func browserName(_ candidate: DetourSetupCandidate) -> String? {
        let known = ["Chrome", "Arc", "Safari", "Brave", "Edge", "Firefox"]
        return known.first { candidateText(candidate).contains($0.lowercased()) }
    }

    func candidateText(_ candidate: DetourSetupCandidate) -> String {
        [
            candidate.id,
            candidate.title,
            candidate.detail,
            candidate.source,
            candidate.prompt ?? "",
            candidate.credentialProviderID ?? "",
            candidate.credentialKeys?.joined(separator: " ") ?? "",
            candidate.category.rawValue,
        ].joined(separator: " ").lowercased()
    }

    @objc func apply(_ sender: NSButton) {
        approved = true
        updateVisualState()
        onApprovalChanged?(candidate.id, true)
    }

    @objc func skip(_ sender: NSButton) {
        approved = false
        updateVisualState()
        onApprovalChanged?(candidate.id, false)
    }

    @objc func scopeUser(_ sender: NSButton) {
        scope = .user
        approved = true
        updateVisualState()
        onScopeChanged?(candidate.id, .user)
    }

    @objc func scopeAgent(_ sender: NSButton) {
        scope = .agent
        approved = true
        updateVisualState()
        onScopeChanged?(candidate.id, .agent)
    }

    @objc func grantPermission(_ sender: NSButton) {
        approved = true
        updateVisualState()
        onApprovalChanged?(candidate.id, true)
        onPermissionRequested?(candidate.id)
    }
}
