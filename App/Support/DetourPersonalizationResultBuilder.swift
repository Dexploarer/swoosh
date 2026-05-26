// DetourPersonalizationResultBuilder.swift — personalization scan result assembly (0.5A)

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
    func buildResult(
        agentName: String,
        userName: String,
        apps: AppInventory,
        appUsage: AppUsageInventory,
        git: GitActivityInventory,
        contacts: ContactInventory,
        messages: MessageInventory,
        auth: AuthInventory,
        agentContextSignals: Set<String>,
        scoutSucceeded: Bool,
        agentContextSucceeded: Bool,
        credentialInheritanceSucceeded: Bool
    ) -> DetourPersonalizationScanResult {
        let installedApps = apps.names.union(agentContextSignals).union(appUsage.topAppNames)
        var candidates = setupCandidates(
            installedApps: installedApps,
            appUsage: appUsage,
            git: git,
            contacts: contacts,
            messages: messages,
            auth: auth
        )
        candidates.append(contentsOf: goalCandidates(installedApps: installedApps, git: git, contacts: contacts))
        candidates.append(contentsOf: scheduleCandidates(installedApps: installedApps, appUsage: appUsage, git: git))

        let signals = signalSummaries(
            apps: apps,
            appUsage: appUsage,
            git: git,
            contacts: contacts,
            messages: messages,
            auth: auth,
            agentContextSignals: agentContextSignals
        )
        let relationships = relationshipCandidates(contacts: contacts, messages: messages)
        let accessItems = candidates
            .filter { $0.category == .permission || $0.category == .context }
            .map { "\($0.title) - \($0.detail)" }
        let accounts = accountSummaries(auth: auth, git: git, contacts: contacts)
        let plugins = candidates
            .filter { $0.category == .connector || $0.category == .model || $0.category == .skill || $0.category == .mcp }
            .map { "\($0.title) - \($0.detail)" }
        let goals = candidates
            .filter { $0.category == .goal }
            .map(\.title)
        let schedules = candidates
            .filter { $0.category == .schedule }
            .map(\.title)
        let questions = questionRecommendations(
            agentName: agentName,
            installedApps: installedApps,
            auth: auth,
            contacts: contacts
        )
        let scanNames = [
            scoutSucceeded ? "Scout" : nil,
            agentContextSucceeded ? "agent-context" : nil,
            credentialInheritanceSucceeded ? "local auth" : nil,
            appUsage.requested ? "app usage" : nil,
            git.requested ? "Git" : nil,
            contacts.requested ? "Contacts" : nil,
            messages.requested ? "Messages" : nil,
        ].compactMap(\.self).joined(separator: " + ")
        let summary = scanNames.isEmpty
            ? "\(agentName) matched installed apps only."
            : "\(agentName) scanned with \(scanNames)."

        return DetourPersonalizationScanResult(
            summary: userName.isEmpty ? summary : "\(summary) For \(userName).",
            signals: signals,
            accessItems: accessItems,
            accounts: accounts,
            goals: goals,
            schedules: schedules,
            plugins: plugins,
            questions: questions,
            setupCandidates: candidates,
            relationshipCandidates: relationships,
            delegationProfiles: delegationProfiles(userName: userName, agentName: agentName, auth: auth, git: git),
            completedAt: .now,
            scoutSucceeded: scoutSucceeded,
            agentContextSucceeded: agentContextSucceeded,
            credentialInheritanceSucceeded: credentialInheritanceSucceeded
        )
    }

}
