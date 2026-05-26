// DetourPersonalizationInventories.swift — personalization app and activity inventory helpers (0.5A)

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
    func appInventory() -> AppInventory {
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            fileManager.homeDirectoryForCurrentUser.appending(path: "Applications"),
            URL(fileURLWithPath: "/System/Applications")
        ]
        var names = Set<String>()
        var displayNames: [String] = []
        for root in roots {
            guard let entries = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
                continue
            }
            for entry in entries where entry.pathExtension == "app" {
                let displayName = entry.deletingPathExtension().lastPathComponent
                names.insert(displayName.lowercased())
                displayNames.append(displayName)
            }
        }
        return AppInventory(names: names, displayNames: displayNames.sorted())
    }

    func appUsageInventory() -> AppUsageInventory {
        let url = fileManager.homeDirectoryForCurrentUser.appending(path: ".swoosh/app-usage.jsonl")
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return AppUsageInventory(requested: true, topApps: [], summary: "App usage log not ready")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var durations: [String: TimeInterval] = [:]
        for line in text.split(separator: "\n").suffix(3_000) {
            guard let data = String(line).data(using: .utf8),
                  let event = try? decoder.decode(AppFocusEventLine.self, from: data) else {
                continue
            }
            let duration = max(0, event.endedAt.timeIntervalSince(event.startedAt))
            durations[event.displayName, default: 0] += duration
        }
        let topApps = durations
            .sorted { $0.value > $1.value }
            .prefix(8)
            .map { AppUsageSummary(displayName: $0.key, duration: $0.value) }
        let summary = topApps.isEmpty
            ? "App usage log has no recent sessions"
            : "Most active: \(topApps.prefix(4).map(\.displayName).joined(separator: ", "))"
        return AppUsageInventory(requested: true, topApps: topApps, summary: summary)
    }

    func gitActivityInventory() -> GitActivityInventory {
        guard let git = executable(named: "git") else {
            return GitActivityInventory(requested: true, repositories: [], gitUserName: nil, gitUserEmail: nil, summary: "Git not found")
        }
        let gitUserName = runProcessOutput(executable: git, arguments: ["config", "--global", "--get", "user.name"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let gitUserEmail = runProcessOutput(executable: git, arguments: ["config", "--global", "--get", "user.email"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        var repositories: [GitRepositoryActivity] = []
        for repo in discoverGitRepositories().prefix(28) {
            guard let output = runProcessOutput(
                executable: git,
                arguments: [
                    "-C", repo.path,
                    "log", "--since=30.days", "--pretty=format:%ct%x09%s", "-n", "4"
                ]
            ), !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            let commits = output.split(separator: "\n").compactMap { line -> GitCommitSignal? in
                let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
                guard parts.count == 2, let timestamp = TimeInterval(parts[0]) else { return nil }
                return GitCommitSignal(date: Date(timeIntervalSince1970: timestamp), subject: parts[1])
            }
            guard let latest = commits.first else { continue }
            repositories.append(GitRepositoryActivity(
                name: repo.lastPathComponent,
                path: repo.path,
                latestCommitDate: latest.date,
                latestSubject: latest.subject,
                commitCount: commits.count
            ))
        }
        repositories.sort { $0.latestCommitDate > $1.latestCommitDate }
        let summary = repositories.isEmpty
            ? "No recent Git activity found"
            : "Active repos: \(repositories.prefix(4).map(\.name).joined(separator: ", "))"
        return GitActivityInventory(
            requested: true,
            repositories: Array(repositories.prefix(12)),
            gitUserName: gitUserName,
            gitUserEmail: gitUserEmail,
            summary: summary
        )
    }

    func contactInventory(allowed: Bool) async -> ContactInventory {
        guard allowed else { return .notRequested }
        #if canImport(Contacts)
        let store = CNContactStore()
        if CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
            let granted = await withCheckedContinuation { continuation in
                store.requestAccess(for: .contacts) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
            guard granted else {
                return ContactInventory(requested: true, authorized: false, totalCount: 0, names: [], organizations: [], summary: "Contacts denied")
            }
        }
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
            return ContactInventory(requested: true, authorized: false, totalCount: 0, names: [], organizations: [], summary: "Contacts unavailable")
        }
        let keys = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactOrganizationNameKey,
            CNContactJobTitleKey,
        ] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var names: [String] = []
        var organizations = Set<String>()
        var total = 0
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                total += 1
                let fullName = [contact.givenName, contact.familyName]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: " ")
                if !fullName.isEmpty, names.count < 40 {
                    names.append(fullName)
                }
                let organization = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !organization.isEmpty {
                    organizations.insert(organization)
                }
            }
        } catch {
            return ContactInventory(requested: true, authorized: true, totalCount: 0, names: [], organizations: [], summary: "Contacts scan failed")
        }
        let orgs = Array(organizations).sorted()
        let summary = total == 0
            ? "No Contacts records found"
            : "\(total) contacts\(orgs.isEmpty ? "" : ", orgs: \(orgs.prefix(3).joined(separator: ", "))")"
        return ContactInventory(
            requested: true,
            authorized: true,
            totalCount: total,
            names: names,
            organizations: orgs,
            summary: summary
        )
        #else
        return ContactInventory(requested: true, authorized: false, totalCount: 0, names: [], organizations: [], summary: "Contacts framework unavailable")
        #endif
    }

    func messageInventory(allowed: Bool) -> MessageInventory {
        guard allowed else { return .notRequested }
        let chatDB = fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Messages/chat.db")
        let exists = fileManager.fileExists(atPath: chatDB.path)
        let readable = fileManager.isReadableFile(atPath: chatDB.path)
        let status: String
        if readable {
            let relationships = imessageRelationshipSignals(chatDB: chatDB)
            status = relationships.isEmpty ? "chat.db readable" : "chat.db readable, \(relationships.count) active handles"
            return MessageInventory(
                requested: true,
                databaseExists: exists,
                databaseReadable: readable,
                relationships: relationships,
                chatDatabaseStatus: status,
                summary: "Messages \(status)"
            )
        } else if exists {
            status = "chat.db present, Full Disk Access likely needed"
        } else {
            status = "Messages database not found"
        }
        return MessageInventory(
            requested: true,
            databaseExists: exists,
            databaseReadable: readable,
            relationships: [],
            chatDatabaseStatus: status,
            summary: "Messages \(status)"
        )
    }

    func imessageRelationshipSignals(chatDB: URL) -> [MessageRelationshipSignal] {
        guard let sqlite = executable(named: "sqlite3") else { return [] }
        let query = """
        SELECT COALESCE(NULLIF(h.id,''), NULLIF(c.display_name,''), 'unknown') || char(9) || COUNT(m.ROWID) || char(9) || COALESCE(MAX(m.date), 0)
        FROM message m
        LEFT JOIN handle h ON m.handle_id = h.ROWID
        LEFT JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        LEFT JOIN chat c ON c.ROWID = cmj.chat_id
        WHERE COALESCE(NULLIF(h.id,''), NULLIF(c.display_name,'')) IS NOT NULL
        GROUP BY COALESCE(NULLIF(h.id,''), NULLIF(c.display_name,''), 'unknown')
        ORDER BY MAX(m.date) DESC
        LIMIT 40;
        """
        guard let output = runProcessOutput(executable: sqlite, arguments: ["-readonly", chatDB.path, query]) else {
            return []
        }
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2,
                  let count = Int(parts[1]),
                  count > 0 else { return nil }
            let handle = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !handle.isEmpty, handle != "unknown" else { return nil }
            return MessageRelationshipSignal(
                handle: handle,
                messageCount: count,
                lastDateRaw: parts.count > 2 ? parts[2] : nil
            )
        }
    }
}
