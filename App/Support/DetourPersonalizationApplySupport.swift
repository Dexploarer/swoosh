// DetourPersonalizationApplySupport.swift — approved setup persistence helpers (0.5A)

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
    func applyCredentialApprovals(
        result: DetourPersonalizationScanResult,
        approvedCandidateIDs: Set<String>
    ) throws -> DetourCredentialApplyResult {
        let approved = result.setupCandidates.filter { approvedCandidateIDs.contains($0.id) }
        let providerIDs = Set(approved.compactMap(\.credentialProviderID))
        var verifiedProviders: Set<String> = []
        if !providerIDs.isEmpty {
            verifiedProviders.formUnion(try runProviderImport(providers: providerIDs))
        }
        let keys = Set(approved.flatMap { $0.credentialKeys ?? [] })
        var legacyResult = DetourLegacyCredentialImportResult(
            vaultFound: false,
            decrypted: false,
            importedKeys: [],
            availableKeys: [],
            error: nil
        )
        if !keys.isEmpty {
            legacyResult = DetourLegacyVaultImporter().importCredentials(
                allowed: true,
                allowUserInteraction: true,
                allowedKeys: keys,
                storeValues: true
            )
        }
        return DetourCredentialApplyResult(
            requestedProviderIDs: providerIDs,
            verifiedProviderIDs: verifiedProviders,
            requestedKeys: keys,
            importedLegacyKeys: Set(legacyResult.importedKeys),
            availableLegacyKeys: Set(legacyResult.availableKeys)
        )
    }

    func runProviderImport(providers: Set<String>) throws -> Set<String> {
        let providerArguments = providers.sorted().flatMap { ["--provider", $0] }
        let arguments = [
            "provider",
            "inherit",
            "--quiet",
            "--allow-keychain",
            "--prompt-keychain",
            "--allow-browser-cookies",
        ] + providerArguments
        guard let command = providerInheritCommand() else {
            throw DetourPersonalizationError.commandFailed(69)
        }
        let output = try runImportCommand(
            executable: command.executable,
            arguments: command.argumentsPrefix + arguments,
            currentDirectory: command.currentDirectory
        )
        return Set(parseProviderImportOutput(output))
    }

    func runImportCommand(executable: URL, arguments: [String], currentDirectory: URL) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw DetourPersonalizationError.commandFailed(process.terminationStatus)
        }
        return text
    }

    func parseProviderImportOutput(_ output: String) -> [String] {
        var values = Set<String>()
        for field in ["discovered", "imported"] {
            guard let range = output.range(of: "\(field)=") else { continue }
            let tail = output[range.upperBound...]
            let token = tail.split(whereSeparator: { $0 == " " || $0 == "\n" }).first.map(String.init) ?? ""
            guard token != "none" else { continue }
            for value in token.split(separator: ",").map(String.init) where !value.isEmpty {
                values.insert(value)
            }
        }
        return Array(values)
    }

    func saveAppliedSetup(
        result: DetourPersonalizationScanResult,
        approvedCandidateIDs: Set<String>,
        deniedCandidateIDs: Set<String>,
        setupCandidateScopes: [String: DetourDelegationRole],
        delegationProfiles: [DetourDelegationProfile]
    ) throws {
        let directory = fileManager.homeDirectoryForCurrentUser.appending(path: ".detour")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let relationshipMapApproved = approvedCandidateIDs.contains("context.relationships")
        let relationships = result.relationshipCandidates.map { candidate in
            var copy = candidate
            copy.selected = relationshipMapApproved && candidate.selected
            return copy
        }
        let applied = DetourPersonalizationAppliedSetup(
            approvedCandidateIDs: Array(approvedCandidateIDs).sorted(),
            deniedCandidateIDs: Array(deniedCandidateIDs).sorted(),
            approvedCandidates: result.setupCandidates.filter { approvedCandidateIDs.contains($0.id) },
            setupCandidateScopes: setupCandidateScopes.mapValues(\.rawValue),
            relationships: relationships,
            delegationProfiles: delegationProfiles,
            savedAt: .now
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(applied)
        try data.write(to: directory.appending(path: "applied-setup.json"), options: .atomic)
    }

    func writeChatAdapterToggles(
        candidates: [DetourSetupCandidate],
        approvedCandidateIDs: Set<String>
    ) throws {
        let mapping = chatAdapterMapping()
        let candidateIDs = Set(candidates.map(\.id))
        let url = fileManager.homeDirectoryForCurrentUser.appending(path: ".swoosh/chat-adapters.json")
        let existing = (try? Data(contentsOf: url))
            .flatMap { try? JSONDecoder().decode([ChatAdapterToggleRecord].self, from: $0) } ?? []
        var toggles: [String: Bool] = [:]
        for record in existing {
            toggles[record.kind] = record.enabled
        }
        for (candidateID, kind) in mapping where candidateIDs.contains(candidateID) {
            toggles[kind] = approvedCandidateIDs.contains(candidateID)
        }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let records = toggles
            .map { ChatAdapterToggleRecord(kind: $0.key, enabled: $0.value) }
            .sorted { $0.kind < $1.kind }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(records)
        try data.write(to: url, options: .atomic)
    }

    func chatAdapterMapping() -> [String: String] {
        [
            "connector.discord": "discord",
            "connector.telegram": "telegram",
            "connector.imessage": "photonIMessage",
            "connector.github": "github",
            "connector.slack": "slack",
            "connector.linear": "linear",
            "connector.agentmail": "agentmail",
            "connector.x": "zernioSocial",
        ]
    }

    func credentialApplicationItem(
        _ credentialCandidates: [DetourSetupCandidate],
        result: DetourCredentialApplyResult,
        setupCandidateScopes: [String: DetourDelegationRole]
    ) -> DetourSetupApplicationItem {
        let userCount = credentialCandidates.filter {
            (setupCandidateScopes[$0.id] ?? $0.scope) == .user
        }.count
        let agentCount = credentialCandidates.filter {
            (setupCandidateScopes[$0.id] ?? $0.scope) == .agent
        }.count
        let parts = [
            userCount > 0 ? "\(userCount) user-owned" : nil,
            agentCount > 0 ? "\(agentCount) agent-owned" : nil,
        ].compactMap(\.self)
        let verifiedCount = credentialCandidates.filter { candidate in
            let providerVerified = candidate.credentialProviderID.map { result.verifiedProviderIDs.contains($0) } ?? false
            let keys = Set(candidate.credentialKeys ?? [])
            let keysVerified = !keys.isEmpty
                && !keys.isDisjoint(with: result.importedLegacyKeys.union(result.availableLegacyKeys))
            return providerVerified || keysVerified
        }.count
        let allVerified = verifiedCount == credentialCandidates.count
        return DetourSetupApplicationItem(
            id: "credentials.apply",
            title: "Credentials",
            detail: parts.isEmpty
                ? "\(verifiedCount) of \(credentialCandidates.count) selected credentials were verified through the agent credential path."
                : "\(verifiedCount) of \(credentialCandidates.count) selected credentials were verified through the agent credential path: \(parts.joined(separator: ", ")).",
            state: allVerified ? .connected : .needsAction,
            doctor: allVerified
                ? nil
                : "Open the items that did not verify, approve Keychain access if macOS prompts, then run Apply setup again."
        )
    }

    func verifyAppliedSetup(
        result: DetourPersonalizationScanResult,
        approvedCandidateIDs: Set<String>,
        deniedCandidateIDs: Set<String>,
        setupCandidateScopes: [String: DetourDelegationRole]
    ) throws -> DetourSetupApplicationItem {
        let url = fileManager.homeDirectoryForCurrentUser
            .appending(path: ".detour")
            .appending(path: "applied-setup.json")
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let applied = try decoder.decode(DetourPersonalizationAppliedSetup.self, from: data)
        guard Set(applied.approvedCandidateIDs) == approvedCandidateIDs else {
            throw DetourSetupVerificationError(errorDescription: "Approved setup choices did not round-trip.")
        }
        guard Set(applied.deniedCandidateIDs) == deniedCandidateIDs else {
            throw DetourSetupVerificationError(errorDescription: "Removed setup choices did not round-trip.")
        }
        let scopedCandidates = result.setupCandidates
            .filter { approvedCandidateIDs.contains($0.id) && candidateNeedsScope($0) }
        var missingScopes: [String] = []
        for candidate in scopedCandidates {
            guard let expected = (setupCandidateScopes[candidate.id] ?? candidate.scope)?.rawValue,
                  applied.setupCandidateScopes[candidate.id] == expected else {
                missingScopes.append(candidate.title)
                continue
            }
        }
        guard missingScopes.isEmpty else {
            throw DetourSetupVerificationError(errorDescription: "Some account ownership choices were not saved.")
        }
        return DetourSetupApplicationItem(
            id: "setup.save",
            title: "Setup file",
            detail: "\(approvedCandidateIDs.count) selected items, \(deniedCandidateIDs.count) removed items, and \(scopedCandidates.count) ownership choices were saved and read back.",
            state: .connected
        )
    }

    func verifyChatAdapterToggles(
        candidates: [DetourSetupCandidate],
        approvedCandidateIDs: Set<String>
    ) throws -> DetourSetupApplicationItem {
        let mapping = chatAdapterMapping()
        let candidateIDs = Set(candidates.map(\.id))
        let url = fileManager.homeDirectoryForCurrentUser.appending(path: ".swoosh/chat-adapters.json")
        let records = try JSONDecoder().decode([ChatAdapterToggleRecord].self, from: Data(contentsOf: url))
        var toggles: [String: Bool] = [:]
        for record in records {
            toggles[record.kind] = record.enabled
        }
        for (candidateID, kind) in mapping where candidateIDs.contains(candidateID) {
            guard toggles[kind] == approvedCandidateIDs.contains(candidateID) else {
                throw DetourSetupVerificationError(errorDescription: "\(kind) connector switch did not round-trip.")
            }
        }
        let enabledCount = mapping
            .filter { candidateIDs.contains($0.key) && approvedCandidateIDs.contains($0.key) }
            .count
        return DetourSetupApplicationItem(
            id: "connectors.save",
            title: "Connectors",
            detail: "\(enabledCount) connector switches were saved and read back.",
            state: .connected
        )
    }

    func candidateNeedsScope(_ candidate: DetourSetupCandidate) -> Bool {
        candidate.scope != nil
            || candidate.prompt != nil
            || candidate.credentialProviderID != nil
            || candidate.credentialKeys?.isEmpty == false
            || candidate.id.hasPrefix("credential.")
    }

    func setupApplicationReport(
        result: DetourPersonalizationScanResult,
        approvedCandidateIDs: Set<String>,
        deniedCandidateIDs: Set<String>,
        setupCandidateScopes: [String: DetourDelegationRole],
        pluginItems: [DetourSetupApplicationItem],
        mcpItems: [DetourSetupApplicationItem],
        failures: [DetourSetupApplicationItem]
    ) -> DetourSetupApplicationReport {
        var items: [DetourSetupApplicationItem] = []
        let approved = result.setupCandidates.filter { approvedCandidateIDs.contains($0.id) }
        let denied = result.setupCandidates.filter { deniedCandidateIDs.contains($0.id) }
        let credentialCandidates = approved.filter(isCredentialCandidate)
        if !credentialCandidates.isEmpty {
            let userCount = credentialCandidates.filter {
                (setupCandidateScopes[$0.id] ?? $0.scope) == .user
            }.count
            let agentCount = credentialCandidates.filter {
                (setupCandidateScopes[$0.id] ?? $0.scope) == .agent
            }.count
            let parts = [
                userCount > 0 ? "\(userCount) for the user's perspective" : nil,
                agentCount > 0 ? "\(agentCount) for the agent's perspective" : nil,
            ].compactMap(\.self)
            items.append(DetourSetupApplicationItem(
                id: "credentials.selected",
                title: "Selected credentials",
                detail: parts.isEmpty
                    ? "\(credentialCandidates.count) selected credentials were saved."
                    : "\(credentialCandidates.count) selected credentials were saved: \(parts.joined(separator: ", ")).",
                state: .connected
            ))
        }
        for candidate in approved.filter({ $0.category == .connector }).sorted(by: { $0.title < $1.title }) {
            items.append(connectorSetupItem(candidate, approved: approved))
        }
        items.append(contentsOf: pluginItems)
        items.append(contentsOf: mcpItems)
        for candidate in denied
            .filter({ $0.category == .connector || $0.category == .model || $0.category == .mcp || $0.category == .skill || isCredentialCandidate($0) })
            .sorted(by: { $0.title < $1.title }) {
            items.append(DetourSetupApplicationItem(
                id: "removed.\(candidate.id)",
                title: candidate.title,
                detail: "Removed from this setup. Detour will not use it unless you add it back later.",
                state: .removed
            ))
        }
        items.append(contentsOf: failures)
        if items.isEmpty {
            items.append(DetourSetupApplicationItem(
                id: "setup.none",
                title: "Setup",
                detail: "No credentials or connectors were selected.",
                state: .removed
            ))
        }
        return DetourSetupApplicationReport(items: items, savedAt: .now)
    }
}
