// DetourPersonalizationBrowserAccountInventory.swift — personalization setup services (0.5A)

import Foundation

@MainActor
extension DetourPersonalizationRunner {
    func githubAccountIdentities(git: GitActivityInventory, keychainItems: [KeychainCredentialMetadata]) -> [GitHubAccountIdentity] {
        var accounts: [GitHubAccountIdentity] = []
        accounts.append(contentsOf: githubAccountsFromGHStatus())
        accounts.append(contentsOf: githubAccountsFromGHHosts())
        for item in keychainItems where item.providerID == "github" {
            guard let owner = githubOwnerLabel(fromKeychainLabel: item.displayLabel) else { continue }
            accounts.append(GitHubAccountIdentity(login: owner, email: nil, source: "Keychain", scope: item.scope))
        }
        if let gitUser = [git.gitUserName, git.gitUserEmail].compactMap(\.self).joinedNonEmpty(separator: " ") {
            accounts.append(GitHubAccountIdentity(login: gitUser, email: git.gitUserEmail, source: "Git config", scope: .user))
        }
        var seen = Set<String>()
        return accounts.filter { account in
            seen.insert("\(account.scope.rawValue):\(account.displayLabel.lowercased())").inserted
        }
    }

    func githubAccountsFromGHStatus() -> [GitHubAccountIdentity] {
        guard let gh = executable(named: "gh"),
              let output = runProcessOutput(executable: gh, arguments: ["auth", "status", "-h", "github.com"]) else {
            return []
        }
        return output.split(separator: "\n").compactMap { line in
            let value = String(line)
            guard let range = value.range(of: "account ") else { return nil }
            let suffix = value[range.upperBound...]
            let login = suffix
                .split { $0.isWhitespace || $0 == "(" }
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let login, !login.isEmpty else { return nil }
            return GitHubAccountIdentity(login: login, email: nil, source: "GitHub CLI", scope: .user)
        }
    }

    func githubAccountsFromGHHosts() -> [GitHubAccountIdentity] {
        let hosts = fileManager.homeDirectoryForCurrentUser.appending(path: ".config/gh/hosts.yml")
        guard let contents = try? String(contentsOf: hosts, encoding: .utf8) else {
            return []
        }
        var inGitHubHost = false
        var accounts: [GitHubAccountIdentity] = []
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.hasPrefix(" ") && !line.hasPrefix("\t") {
                inGitHubHost = trimmed == "github.com:"
                continue
            }
            guard inGitHubHost, trimmed.hasPrefix("user:") else { continue }
            let login = trimmed
                .dropFirst("user:".count)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
            guard !login.isEmpty else { continue }
            accounts.append(GitHubAccountIdentity(login: login, email: nil, source: "GitHub CLI config", scope: .user))
        }
        return accounts
    }

    func githubOwnerLabel(
        scope: DetourDelegationRole,
        git: GitActivityInventory,
        keychainItems: [KeychainCredentialMetadata],
        githubAccounts: [GitHubAccountIdentity]
    ) -> String? {
        if let account = githubAccounts.first(where: { $0.scope == scope }) {
            return account.displayLabel
        }
        if let owner = keychainItems
            .filter({ $0.providerID == "github" && $0.scope == scope })
            .compactMap({ githubOwnerLabel(fromKeychainLabel: $0.displayLabel) })
            .first {
            return owner
        }
        guard scope == .user else { return nil }
        return [git.gitUserName, git.gitUserEmail].compactMap(\.self).joinedNonEmpty(separator: " ")
    }

    func githubOwnerLabel(fromKeychainLabel label: String) -> String? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowercased = trimmed.lowercased()
        let genericMarkers = [
            "github",
            "gh:github.com",
            "copilot",
            "safe storage",
            "credential",
            "credentials",
            "token",
            "auth",
        ]
        if genericMarkers.contains(where: { lowercased == $0 || lowercased.contains($0) }) {
            return nil
        }
        return trimmed
    }

    func browserAccountTitle(_ account: BrowserAccountFinding) -> String {
        if account.account.contains("@") {
            return "X session in \(account.browser) profile \(browserAccountOwnerLabel(account) ?? account.account)"
        }
        if let owner = browserAccountOwnerLabel(account) {
            return "X session for @\(account.account) in \(account.browser) (\(owner))"
        }
        return "X session for @\(account.account) in \(account.browser)"
    }

    func browserAccountDetail(_ account: BrowserAccountFinding) -> String {
        var parts = ["\(account.profile) profile"]
        if let owner = browserAccountOwnerLabel(account) {
            parts.append(account.account.contains("@") ? "signed in as \(owner)" : "Google account \(owner)")
        }
        parts.append(account.evidence)
        return parts.joined(separator: "; ")
    }

    func browserAccountSummary(_ account: BrowserAccountFinding) -> String {
        if account.account.contains("@") {
            return "\(account.browser) profile \(browserAccountOwnerLabel(account) ?? account.account)"
        }
        if let owner = browserAccountOwnerLabel(account) {
            return "@\(account.account) in \(account.browser) (\(owner))"
        }
        return "@\(account.account) in \(account.browser)"
    }

    func browserAccountOwnerLabel(_ account: BrowserAccountFinding) -> String? {
        let email = account.profileEmail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let name = usefulBrowserProfileName(account.profileName, profile: account.profile, email: email)
        if let name, let email, name.caseInsensitiveCompare(email) != .orderedSame {
            return "\(name) (\(email))"
        }
        return name ?? email ?? (account.account.contains("@") ? account.account : nil)
    }

    func usefulBrowserProfileName(_ value: String?, profile: String, email: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }
        let lowercased = trimmed.lowercased()
        let genericNames = [
            "default",
            "guest",
            "profile",
            "profile 1",
            "profile 2",
            "person 1",
            "person 2",
        ]
        if genericNames.contains(lowercased) || lowercased == profile.lowercased() {
            return nil
        }
        if lowercased.hasPrefix("profile "), let email {
            return email
        }
        return trimmed
    }
}
