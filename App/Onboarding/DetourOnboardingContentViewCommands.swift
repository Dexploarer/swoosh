// DetourOnboardingContentViewCommands.swift — Detour onboarding view slice (0.5A)

import AppKit
import QuartzCore

extension DetourOnboardingContentView {
    func applyPersonalizationSelectionCommand(_ command: String) -> Bool {
        if commandContains(command, ["use all", "enable all", "select all", "allow all"]) {
            store.selectAllPersonalizationCandidates()
            return true
        }
        if commandContains(command, ["skip all", "none", "nothing"]) {
            store.clearPersonalizationCandidates()
            return true
        }
        let credentialTerms = personalizationCredentialTerms(from: command)
        if commandContains(command, ["agent scoped", "as agent", "for agent", "as detour", "for detour", "agent account"]) {
            store.setPersonalizationCandidateScope(matching: credentialTerms, role: .agent)
            return true
        }
        if commandContains(command, ["user scoped", "as me", "for me", "personal account", "my account"]) {
            store.setPersonalizationCandidateScope(matching: credentialTerms, role: .user)
            return true
        }
        if isAffirmative(command) || commandContains(command, ["apply", "use this", "use these", "approve"]) {
            store.selectPersonalizationCandidates(matching: credentialTerms.isEmpty ? ["credential"] : credentialTerms)
            return true
        }
        if isNegative(command) || commandContains(command, ["skip this", "skip these", "deny", "do not apply"]) {
            store.excludePersonalizationCandidates(matching: credentialTerms.isEmpty ? ["credential"] : credentialTerms)
            return true
        }
        if commandContains(command, ["no cookies", "no browser", "exclude browser"]) {
            store.excludePersonalizationCandidates(matching: ["cookie", "browser", "x "])
            return true
        }
        if commandContains(command, ["no legacy", "exclude legacy", "no old detour"]) {
            store.excludePersonalizationCandidates(matching: ["legacy", "old detour"])
            return true
        }
        if commandContains(command, ["no contacts", "exclude contacts"]) {
            store.excludePersonalizationCandidates(matching: ["contact"])
            return true
        }
        if commandContains(command, ["no messages", "no imessage", "exclude messages"]) {
            store.excludePersonalizationCandidates(matching: ["message", "imessage"])
            return true
        }
        if commandContains(command, ["no relationships", "exclude relationships"]) {
            store.excludePersonalizationCandidates(matching: ["relationship", "contact", "message", "imessage"])
            return true
        }
        if commandContains(command, ["no mcp", "exclude mcp", "no tool servers"]) {
            store.excludePersonalizationCandidates(matching: ["mcp", "tool server"])
            return true
        }
        if commandContains(command, ["messaging only"]) {
            store.clearPersonalizationCandidates()
            store.selectPersonalizationCandidates(matching: ["discord", "telegram", "message", "imessage", "slack", "relationship"])
            return true
        }
        if commandContains(command, ["relationships only", "people only"]) {
            store.clearPersonalizationCandidates()
            store.selectPersonalizationCandidates(matching: ["relationship", "contact", "message", "imessage"])
            return true
        }
        if commandContains(command, ["developer only", "coding only"]) {
            store.clearPersonalizationCandidates()
            store.selectPersonalizationCandidates(matching: ["git", "github", "repo", "xcode", "cursor"])
            return true
        }
        return false
    }

    func personalizationCredentialTerms(from command: String) -> [String] {
        var terms: [String] = []
        if commandContains(command, ["openai", "open ai"]) { terms.append("openai") }
        if commandContains(command, ["openrouter", "open router"]) { terms.append("openrouter") }
        if commandContains(command, ["eliza", "eliza cloud"]) { terms.append("eliza") }
        if commandContains(command, ["claude", "anthropic"]) { terms.append("claude") }
        if commandContains(command, ["gemini", "google ai"]) { terms.append("gemini") }
        if commandContains(command, ["codex", "chatgpt", "chat gpt"]) { terms.append("codex") }
        if commandContains(command, ["github"]) { terms.append("github") }
        if commandContains(command, ["discord"]) { terms.append("discord") }
        if commandContains(command, ["telegram"]) { terms.append("telegram") }
        if commandContains(command, ["agentmail", "agent mail"]) { terms.append("agentmail") }
        if commandContains(command, ["slack"]) { terms.append("slack") }
        if commandContains(command, ["notion"]) { terms.append("notion") }
        if commandContains(command, ["linear"]) { terms.append("linear") }
        if commandContains(command, ["mcp", "tool server", "tool servers"]) { terms.append("mcp") }
        if commandContains(command, ["detour squirrel", "detour_squirrel"]) { terms.append("detour_squirrel") }
        if commandContains(command, ["dexploarer"]) { terms.append("dexploarer") }
        if commandContains(command, ["twitter", "x account", "x.com"]) { terms.append("x ") }
        if commandContains(command, ["browser", "cookies", "sessions"]) { terms.append("browser") }
        if commandContains(command, ["legacy", "old detour"]) { terms.append("legacy") }
        return terms
    }

    func commandMentions(_ device: DetourDeviceKind, in command: String) -> Bool {
        switch device {
        case .macBook:
            return command.contains("macbook") || command.contains("mac book") || command.contains("laptop")
        case .macMini:
            return command.contains("mac mini") || command.contains("mini")
        case .iPhone:
            return command.contains("iphone") || command.contains("phone")
        case .iPad:
            return command.contains("ipad") || command.contains("tablet")
        case .appleWatch:
            return command.contains("apple watch") || command.contains("watch")
        case .iMac:
            return command.contains("imac")
        case .macStudio:
            return command.contains("mac studio") || command.contains("studio")
        case .visionPro:
            return command.contains("vision") || command.contains("vision pro")
        case .remoteDetour:
            return command.contains("remote") || command.contains("server")
        }
    }

    func cleanedSpokenValue(_ transcript: String) -> String {
        transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:"))
    }

    func spokenValue(_ value: String, dropping prefixes: [String]) -> String {
        let normalizedValue = removingLeadingFillers(from: value)
        let lowercased = normalizedValue.lowercased()
        for prefix in prefixes where lowercased.hasPrefix(prefix) {
            return String(normalizedValue.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:"))
        }
        return normalizedValue
    }

    func cleanName(_ value: String) -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased() == "detour" {
            return ""
        }
        return name
    }

    func spokenAgentNameCandidate(_ value: String, allowBareName: Bool) -> String? {
        let normalizedValue = removingLeadingFillers(from: value)
        let explicitPrefixes = [
            "call you",
            "call yourself",
            "name you",
            "name it",
            "your name is",
            "you are",
            "you're",
            "rename you to",
            "change your name to",
            "let's call you",
            "lets call you",
            "i'll call you",
            "ill call you"
        ]
        let lowercased = normalizedValue.lowercased()
        let explicitCandidate = explicitPrefixes.compactMap { prefix -> String? in
            guard lowercased.hasPrefix(prefix) else { return nil }
            return String(normalizedValue.dropFirst(prefix.count))
        }.first
        guard let candidate = explicitCandidate ?? (allowBareName ? normalizedValue : nil) else {
            return nil
        }
        return cleanedAgentNameCandidate(candidate)
    }

    func cleanedAgentNameCandidate(_ value: String) -> String? {
        let candidate = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:"))
        guard !candidate.isEmpty else { return nil }
        let lowercased = candidate.lowercased()
        let selfIntroTerms = ["my name", "i'm", "i am", "im ", "it's me", "its me", "this is"]
        guard !commandContains(lowercased, selfIntroTerms) else { return nil }
        guard !namesMatch(candidate, store.userName) else { return nil }
        guard !containsName(candidate, store.userName) else { return nil }
        return candidate
    }

    func removingLeadingFillers(from value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let fillers = ["hey ", "hi ", "hello ", "yo "]
        while let filler = fillers.first(where: { result.lowercased().hasPrefix($0) }) {
            result = String(result.dropFirst(filler.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        == rhs.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    func containsName(_ value: String, _ name: String) -> Bool {
        let canonicalValue = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let canonicalName = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !canonicalName.isEmpty else { return false }
        return canonicalValue
            .split { !$0.isLetter && !$0.isNumber }
            .contains { String($0) == canonicalName }
    }

    func commandContains(_ command: String, _ terms: [String]) -> Bool {
        terms.contains { command.contains($0) }
    }

    func isAffirmative(_ command: String) -> Bool {
        commandContains(command, ["yes", "yeah", "yep", "sure", "ok", "okay", "please", "do it"])
    }

    func isNegative(_ command: String) -> Bool {
        commandContains(command, ["no", "nope", "later", "not now", "skip"])
    }

    func isBackCommand(_ command: String) -> Bool {
        command == "back"
            || command == "go back"
            || command == "previous"
            || command == "go previous"
            || command == "change that"
            || command == "redo that"
    }

    func isContinueCommand(_ command: String) -> Bool {
        commandContains(command, ["continue", "done", "next", "save", "submit", "that's it", "that is it"])
    }

}
