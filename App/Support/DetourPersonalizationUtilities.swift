// DetourPersonalizationUtilities.swift — shared personalization file and report helpers (0.5A)

import AppKit
#if canImport(Contacts)
import Contacts
#endif
import Foundation
import OSLog
#if canImport(Security)
import Security
#endif

@MainActor
extension DetourPersonalizationRunner {
    func credentialKeyMentions(keys: [String]) -> Set<String> {
        var found = Set<String>()
        let environment = ProcessInfo.processInfo.environment
        for key in keys where environment[key]?.isEmpty == false {
            found.insert(key)
        }
        let home = fileManager.homeDirectoryForCurrentUser
        let files = [
            home.appending(path: ".zshrc"),
            home.appending(path: ".zprofile"),
            home.appending(path: ".bash_profile"),
            home.appending(path: ".swoosh/config.json"),
            home.appending(path: ".detour/profile.json"),
            home.appending(path: ".codex/auth.json"),
            home.appending(path: ".codex/config.toml"),
            home.appending(path: ".claude.json"),
            home.appending(path: ".claude/settings.json"),
            home.appending(path: ".config/gh/hosts.yml"),
            home.appending(path: ".gemini/settings.json"),
            home.appending(path: ".config/gemini/settings.json"),
            home.appending(path: ".config/anthropic/credentials.json"),
        ]
        for file in files {
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey]),
                  (values.fileSize ?? 0) <= 1_000_000,
                  let text = try? String(contentsOf: file, encoding: .utf8) else {
                continue
            }
            for key in keys where text.contains(key) {
                found.insert(key)
            }
        }
        return found
    }

    func discoverGitRepositories() -> [URL] {
        let home = fileManager.homeDirectoryForCurrentUser
        let roots = [
            Self.projectRoot,
            home.appending(path: "Documents"),
            home.appending(path: "Developer"),
            home.appending(path: "Projects"),
            home.appending(path: ".codex/worktrees"),
        ]
        let excluded = Set([
            "Library", "Applications", "Movies", "Music", "Pictures", "Downloads",
            "node_modules", ".build", "DerivedData", ".git", ".swiftpm", ".cache"
        ])
        var repos: [URL] = []
        var seen = Set<String>()
        var pending = roots.map { ($0, 0) }
        while !pending.isEmpty && repos.count < 40 {
            let (url, depth) = pending.removeFirst()
            let path = url.path
            guard seen.insert(path).inserted else { continue }
            guard directoryExists(url) else { continue }
            if fileManager.fileExists(atPath: url.appending(path: ".git").path) {
                repos.append(url)
                continue
            }
            guard depth < 3,
                  let children = try? fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsPackageDescendants]
                  ) else {
                continue
            }
            for child in children {
                let name = child.lastPathComponent
                guard !excluded.contains(name),
                      (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                    continue
                }
                pending.append((child, depth + 1))
            }
        }
        return repos
    }

    func runProcessOutput(
        executable: URL,
        arguments: [String],
        currentDirectory: URL? = nil
    ) -> String? {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = output
        process.standardError = error
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    func messageDateDescription(raw: String?) -> String? {
        guard let raw,
              let value = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              value > 0 else { return nil }
        let seconds = value > 10_000_000_000 ? value / 1_000_000_000 : value
        let date = Date(timeIntervalSinceReferenceDate: seconds)
        guard date > Date(timeIntervalSince1970: 0),
              date < Date().addingTimeInterval(60 * 60 * 24) else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    func stableIDComponent(_ value: String) -> String {
        let mapped = value.lowercased().unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "-"
        }.joined()
        let compacted = mapped.split(separator: "-").joined(separator: "-")
        return String(compacted.prefix(64)).nilIfEmpty ?? "unknown"
    }

    func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func candidate(
        id: String,
        category: DetourSetupCategory,
        title: String,
        detail: String,
        source: String,
        recommended: Bool,
        prompt: String? = nil,
        foundCount: Int? = nil,
        credentialProviderID: String? = nil,
        credentialKeys: [String]? = nil,
        scope: DetourDelegationRole? = nil
    ) -> DetourSetupCandidate {
        DetourSetupCandidate(
            id: id,
            category: category,
            title: title,
            detail: detail,
            source: source,
            recommended: recommended,
            selected: recommended,
            prompt: prompt,
            foundCount: foundCount,
            credentialProviderID: credentialProviderID,
            credentialKeys: credentialKeys,
            scope: scope
        )
    }

    func hasGitHubSignals(installedApps: Set<String>, auth: AuthInventory) -> Bool {
        containsAny(["github desktop", "github", "xcode", "visual studio code", "cursor"], in: installedApps)
            || auth.hasAny(["GITHUB_TOKEN", "GITHUB_USER_PAT", "GITHUB_AGENT_PAT"])
    }

    func hasBrowser(_ installedApps: Set<String>) -> Bool {
        containsAny(["safari", "google chrome", "arc", "brave browser", "firefox"], in: installedApps)
    }

    func hasAppleProductivity(_ installedApps: Set<String>) -> Bool {
        containsAny(["calendar", "reminders", "mail", "messages"], in: installedApps)
    }

    func containsAny(_ matches: [String], in installedApps: Set<String>) -> Bool {
        installedApps.contains { app in
            matches.contains { app.contains($0) }
        }
    }

    func agentContextSignals() -> Set<String> {
        guard let reviewDirectory = latestAgentContextReviewDirectory() else { return [] }
        let targets = [
            "slack", "discord", "telegram", "github", "notion", "linear", "obsidian",
            "docker", "safari", "google chrome", "arc", "brave browser", "firefox",
            "calendar", "reminders", "mail", "messages", "xcode", "visual studio code", "cursor",
            "openai", "openrouter", "x.com", "twitter", "imessage"
        ]
        var signals = Set<String>()
        guard let enumerator = fileManager.enumerator(at: reviewDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return signals
        }
        var filesRead = 0
        for case let fileURL as URL in enumerator {
            guard filesRead < 120 else { break }
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                  (values.fileSize ?? 0) < 2_000_000,
                  let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }
            filesRead += 1
            let lowercased = contents.lowercased()
            for target in targets where lowercased.contains(target) {
                signals.insert(target)
            }
        }
        return signals
    }

    func latestAgentContextReviewDirectory() -> URL? {
        let reviewRoot = fileManager.homeDirectoryForCurrentUser
            .appending(path: ".agent-context")
            .appending(path: "review")
        guard let entries = try? fileManager.contentsOfDirectory(
            at: reviewRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey]
        ) else {
            return nil
        }
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .max { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left < right
            }
    }

    func executable(named name: String) -> URL? {
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            home.appending(path: ".local/bin/\(name)"),
            URL(fileURLWithPath: "/opt/homebrew/bin/\(name)"),
            URL(fileURLWithPath: "/usr/local/bin/\(name)"),
            URL(fileURLWithPath: "/usr/bin/\(name)")
        ]
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    func providerInheritCommand(logHandle: FileHandle? = nil) -> ProviderInheritCommand? {
        guard let swoosh = executable(named: "swoosh") else {
            appendLog("Provider inherit unavailable: swoosh executable not found.", to: logHandle)
            return nil
        }
        guard commandSupportsProviderInherit(executable: swoosh, argumentsPrefix: []) else {
            appendLog("Provider inherit unavailable: \(swoosh.path) does not support provider inherit.", to: logHandle)
            return nil
        }
        return ProviderInheritCommand(executable: swoosh, argumentsPrefix: [], currentDirectory: Self.projectRoot)
    }

    func commandSupportsProviderInherit(executable: URL, argumentsPrefix: [String]) -> Bool {
        guard let output = runProcessOutput(
            executable: executable,
            arguments: argumentsPrefix + ["provider", "--help"]
        ) else {
            return false
        }
        return output.split(whereSeparator: \.isNewline).contains { line in
            line.trimmingCharacters(in: .whitespaces).hasPrefix("inherit")
        }
    }

    func appendLog(_ message: String, to logHandle: FileHandle?) {
        guard let data = (message + "\n").data(using: .utf8) else { return }
        logHandle?.write(data)
    }

    func prepareLogURL() -> URL {
        let directory = fileManager.homeDirectoryForCurrentUser
            .appending(path: ".detour")
            .appending(path: "logs")
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "personalization.log")
        fileManager.createFile(atPath: url.path, contents: nil)
        return url
    }

    func saveReport(_ result: DetourPersonalizationScanResult) {
        do {
            let directory = fileManager.homeDirectoryForCurrentUser.appending(path: ".detour")
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(DetourStateStore().sanitizedPersonalizationReport(result))
            try data.write(to: directory.appending(path: "personalization-report.json"), options: .atomic)
        } catch {
            logger.error("[DetourPersonalizationRunner] Failed to save personalization report \(error.localizedDescription, privacy: .public)")
        }
    }
}
