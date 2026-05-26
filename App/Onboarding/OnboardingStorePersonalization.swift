// OnboardingStorePersonalization.swift — onboarding state extension (0.5A)

import Foundation

@MainActor
extension OnboardingStore {
    func completeDeviceSetup() {
        step = .askingPersonalizationScan
        saveProfile(onboardingCompleted: false)
    }

    var personalizationReviewText: String {
        restoreSavedPersonalizationReportIfNeeded()
        guard let result = personalizationResult else { return "" }
        let credentialPrompts = result.setupCandidates
            .filter { $0.prompt != nil }
            .map { candidate in
                let scope = setupCandidateScopes[candidate.id] ?? candidate.scope
                let scopeText = scope.map(reviewScopeDescription) ?? "saved without a perspective"
                let selectedText = deniedSetupCandidateIDs.contains(candidate.id) ? "removed" : "selected"
                return "\(candidate.title) - \(scopeText) - \(selectedText)"
            }
            .joined(separator: "\n")
        let signals = result.signals.joined(separator: "\n")
        let access = result.accessItems.joined(separator: "\n")
        let accounts = result.accounts.joined(separator: "\n")
        let plugins = result.plugins.joined(separator: "\n")
        let goals = result.goals.joined(separator: "\n")
        let relationships = result.relationshipCandidates
            .prefix(12)
            .map { candidate in
                if let count = candidate.messageCount {
                    return "\(candidate.displayName) - \(count) messages"
                }
                return "\(candidate.displayName) - \(candidate.source)"
            }
            .joined(separator: "\n")
        return [
            section("Credentials", credentialPrompts),
            section("Signals", signals),
            section("Access", access),
            section("Accounts", accounts),
            section("Relationships", relationships),
            section("Plugins", plugins),
            section("Goals", goals)
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    var personalizationReviewHasContent: Bool {
        restoreSavedPersonalizationReportIfNeeded()
        if setupApplicationReport != nil { return true }
        guard let result = personalizationResult else { return false }
        return result.setupCandidates.contains { !deniedSetupCandidateIDs.contains($0.id) }
    }

    func reviewScopeDescription(_ role: DetourDelegationRole) -> String {
        switch role {
        case .user:
            let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
            return "use as \(name.isEmpty ? "the user" : name)"
        case .agent:
            let name = agentName.trimmingCharacters(in: .whitespacesAndNewlines)
            return "use as \(name.isEmpty ? Self.defaultAgentName : name)"
        }
    }

    func skipPersonalizationScan() {
        completeOnboarding()
    }

    func askCredentialInheritanceForPersonalization() {
        step = .askingCredentialInheritance
        saveProfile(onboardingCompleted: false)
    }

    func setCredentialInheritanceConsent(_ allowed: Bool) {
        credentialInheritanceConsent = allowed ? .fullPersonalization() : DetourCredentialInheritanceConsent()
        saveProfile(onboardingCompleted: false)
    }

    func startPersonalizationScan() {
        personalizationProgress = .idle
        personalizationResult = nil
        approvedSetupCandidateIDs = []
        deniedSetupCandidateIDs = []
        setupCandidateScopes = [:]
        setupApplicationReport = nil
        step = .runningPersonalizationScan
        saveProfile(onboardingCompleted: false)
    }

    func runPersonalizationScan(
        onProgress: @escaping @MainActor (DetourPersonalizationProgress) -> Void
    ) async {
        let scannedResult = await setupGraph.scan(
            agentName: agentName,
            userName: userName,
            credentialConsent: credentialInheritanceConsent
        ) { [weak self] progress in
            self?.personalizationProgress = progress
            onProgress(progress)
        }
        let result = stateStore.sanitizedPersonalizationReport(scannedResult)
        personalizationResult = result
        approvedSetupCandidateIDs = Set(result.setupCandidates.filter(\.selected).map(\.id))
        deniedSetupCandidateIDs = Set(result.setupCandidates.filter { !$0.selected }.map(\.id))
        setupCandidateScopes = defaultSetupCandidateScopes(result.setupCandidates)
        setupApplicationReport = nil
        delegationProfiles = result.delegationProfiles
        personalizationProgress = .complete
        step = .reviewingPersonalizationScan
        saveProfile(onboardingCompleted: false)
    }

    func selectAllPersonalizationCandidates() {
        guard let result = personalizationResult else { return }
        approvedSetupCandidateIDs = Set(result.setupCandidates.map(\.id))
        deniedSetupCandidateIDs = []
        setupApplicationReport = nil
        saveProfile(onboardingCompleted: false)
    }

    func clearPersonalizationCandidates() {
        guard let result = personalizationResult else { return }
        approvedSetupCandidateIDs = []
        deniedSetupCandidateIDs = Set(result.setupCandidates.map(\.id))
        setupApplicationReport = nil
        saveProfile(onboardingCompleted: false)
    }

    func excludePersonalizationCandidates(matching terms: [String]) {
        guard let result = personalizationResult else { return }
        let matches = Set(
            result.setupCandidates
                .filter { candidate in
                    let value = [
                        candidate.title,
                        candidate.detail,
                        candidate.category.rawValue,
                        candidate.source,
                        candidate.prompt ?? "",
                        candidate.credentialProviderID ?? "",
                        candidate.credentialKeys?.joined(separator: " ") ?? "",
                    ].joined(separator: " ").lowercased()
                    return terms.contains { value.contains($0) }
                }
                .map(\.id)
        )
        approvedSetupCandidateIDs.subtract(matches)
        deniedSetupCandidateIDs.formUnion(matches)
        setupApplicationReport = nil
        saveProfile(onboardingCompleted: false)
    }

    func selectPersonalizationCandidates(matching terms: [String]) {
        guard let result = personalizationResult else { return }
        let matches = Set(
            result.setupCandidates
                .filter { candidate in
                    let value = [
                        candidate.title,
                        candidate.detail,
                        candidate.category.rawValue,
                        candidate.source,
                        candidate.prompt ?? "",
                        candidate.credentialProviderID ?? "",
                        candidate.credentialKeys?.joined(separator: " ") ?? "",
                    ].joined(separator: " ").lowercased()
                    return terms.contains { value.contains($0) }
                }
                .map(\.id)
        )
        approvedSetupCandidateIDs.formUnion(matches)
        deniedSetupCandidateIDs.subtract(matches)
        setupApplicationReport = nil
        saveProfile(onboardingCompleted: false)
    }

    func setPersonalizationCandidateScope(matching terms: [String], role: DetourDelegationRole) {
        guard let result = personalizationResult else { return }
        let matches = result.setupCandidates
            .filter { candidate in
                let value = [
                    candidate.title,
                    candidate.detail,
                    candidate.category.rawValue,
                    candidate.source,
                    candidate.prompt ?? "",
                    candidate.credentialProviderID ?? "",
                    candidate.credentialKeys?.joined(separator: " ") ?? "",
                ].joined(separator: " ").lowercased()
                let isCredential = candidate.prompt != nil || candidate.credentialProviderID != nil || candidate.credentialKeys?.isEmpty == false
                return terms.isEmpty ? isCredential : terms.contains { value.contains($0) }
            }
            .map(\.id)
        for id in matches {
            setupCandidateScopes[id] = role
            approvedSetupCandidateIDs.insert(id)
            deniedSetupCandidateIDs.remove(id)
        }
        setupApplicationReport = nil
        saveProfile(onboardingCompleted: false)
    }

    func setPersonalizationCandidateApproval(id: String, approved: Bool) {
        guard personalizationResult?.setupCandidates.contains(where: { $0.id == id }) == true else { return }
        if approved {
            approvedSetupCandidateIDs.insert(id)
            deniedSetupCandidateIDs.remove(id)
        } else {
            approvedSetupCandidateIDs.remove(id)
            deniedSetupCandidateIDs.insert(id)
        }
        setupApplicationReport = nil
        saveProfile(onboardingCompleted: false)
    }

    func setPersonalizationCandidateScope(id: String, role: DetourDelegationRole) {
        guard personalizationResult?.setupCandidates.contains(where: { $0.id == id }) == true else { return }
        setupCandidateScopes[id] = role
        approvedSetupCandidateIDs.insert(id)
        deniedSetupCandidateIDs.remove(id)
        setupApplicationReport = nil
        saveProfile(onboardingCompleted: false)
    }

    func personalizationCandidateScope(_ candidate: DetourSetupCandidate) -> DetourDelegationRole? {
        setupCandidateScopes[candidate.id] ?? candidate.scope
    }

    func personalizationCandidateIsApproved(_ candidate: DetourSetupCandidate) -> Bool {
        !deniedSetupCandidateIDs.contains(candidate.id)
    }

    func defaultSetupCandidateScopes(_ candidates: [DetourSetupCandidate]) -> [String: DetourDelegationRole] {
        Dictionary(uniqueKeysWithValues: candidates.compactMap { candidate in
            candidate.scope.map { (candidate.id, $0) }
        })
    }

    @discardableResult
    func continueFromPersonalizationReview() -> Bool {
        restoreSavedPersonalizationReportIfNeeded()
        guard personalizationResult != nil else {
            completeOnboarding()
            return true
        }
        if setupApplicationReport == nil {
            return false
        }
        completeOnboarding()
        return true
    }

    @discardableResult
    func applySetupFromPersonalizationReview(
        onProgress: @escaping @MainActor (DetourSetupApplicationReport) -> Void
    ) async -> Bool {
        restoreSavedPersonalizationReportIfNeeded()
        guard let result = personalizationResult else {
            completeOnboarding()
            return true
        }
        guard setupApplicationReport == nil, !isApplyingSetup else {
            return continueFromPersonalizationReview()
        }
        isApplyingSetup = true
        let initialReport = DetourSetupApplicationReport(
            items: [
                DetourSetupApplicationItem(
                    id: "setup.start",
                    title: "Setup check",
                    detail: "Starting setup, save, and health checks.",
                    state: .checking
                )
            ],
            savedAt: .now
        )
        setupApplicationReport = initialReport
        onProgress(initialReport)
        saveProfile(onboardingCompleted: false)
        let report = await setupGraph.apply(
            result: result,
            approvedCandidateIDs: approvedSetupCandidateIDs,
            deniedCandidateIDs: deniedSetupCandidateIDs,
            setupCandidateScopes: setupCandidateScopes,
            delegationProfiles: delegationProfiles
        ) { [weak self] report in
            self?.setupApplicationReport = report
            onProgress(report)
            self?.saveProfile(onboardingCompleted: false)
        }
        setupApplicationReport = report
        isApplyingSetup = false
        saveProfile(onboardingCompleted: false)
        onProgress(report)
        return false
    }

    func prepareForPermissionRestart() {
        if step == .runningPersonalizationScan
            || step == .reviewingPersonalizationScan {
            personalizationResult = nil
            setupApplicationReport = nil
            personalizationProgress = .idle
            step = .runningPersonalizationScan
            do {
                try stateStore.deletePersonalizationReport()
                storageError = nil
            } catch {
                storageError = error.localizedDescription
            }
        }
        saveProfile(onboardingCompleted: false)
    }
}
