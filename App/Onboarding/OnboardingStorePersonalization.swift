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
                return DetourSetupInsightRedaction.display("\(candidate.title) - \(scopeText) - \(selectedText)")
            }
            .joined(separator: "\n")
        let signals = result.signals.map(DetourSetupInsightRedaction.display).joined(separator: "\n")
        let access = result.accessItems.map(DetourSetupInsightRedaction.display).joined(separator: "\n")
        let accounts = result.accounts.map(DetourSetupInsightRedaction.display).joined(separator: "\n")
        let plugins = result.plugins.map(DetourSetupInsightRedaction.display).joined(separator: "\n")
        let goals = result.goals.map(DetourSetupInsightRedaction.display).joined(separator: "\n")
        let relationships = result.relationshipCandidates
            .prefix(12)
            .map { candidate in
                if let count = candidate.messageCount {
                    return DetourSetupInsightRedaction.display("\(candidate.displayName) - \(count) messages")
                }
                return DetourSetupInsightRedaction.display("\(candidate.displayName) - \(candidate.source)")
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
            return "use as \(name.isEmpty ? "the user" : DetourSetupInsightRedaction.display(name))"
        case .agent:
            let name = agentName.trimmingCharacters(in: .whitespacesAndNewlines)
            return "use as \(name.isEmpty ? Self.defaultAgentName : DetourSetupInsightRedaction.display(name))"
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
        saveProfile(onboardingCompleted: step == .complete)
    }

    func saveHomeConfiguration(
        userName newUserName: String,
        agentName newAgentName: String,
        wakeWord newWakeWord: String,
        voiceRecognitionEnabled: Bool,
        credentialConsent consent: DetourCredentialInheritanceConsent
    ) {
        let nextUserName = trimmed(newUserName)
        let nextAgentName = trimmed(newAgentName)
        let nextWakeWord = trimmed(newWakeWord)
        if !nextUserName.isEmpty {
            userName = nextUserName
            userNameDraft = nextUserName
        }
        if !nextAgentName.isEmpty {
            agentName = nextAgentName
            agentNameDraft = nextAgentName
        }
        voiceRecognition.wakeWord = nextWakeWord.isEmpty ? defaultWakeWord : nextWakeWord
        voiceRecognition.enabled = voiceRecognitionEnabled
        wakeWordDraft = voiceRecognition.wakeWord
        credentialInheritanceConsent = consent
        saveProfile(onboardingCompleted: step == .complete)
    }

    func saveHomeModelSelection(providerID: String?, modelID: String?) {
        config.preferredProviderID = providerID
        config.preferredModelID = modelID
        config.updatedAt = .now
        saveConfig()
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

    func startInAppConfigurationScan() {
        personalizationProgress = .idle
        personalizationResult = nil
        approvedSetupCandidateIDs = []
        deniedSetupCandidateIDs = []
        setupCandidateScopes = [:]
        setupApplicationReport = nil
        saveProfile(onboardingCompleted: step == .complete)
    }

    func runInAppConfigurationScan(
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
        saveProfile(onboardingCompleted: step == .complete)
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
        saveProfile(onboardingCompleted: step == .complete)
    }

    func selectAllPersonalizationCandidates() {
        guard let result = personalizationResult else { return }
        approvedSetupCandidateIDs = Set(result.setupCandidates.map(\.id))
        deniedSetupCandidateIDs = []
        setupApplicationReport = nil
        saveProfile(onboardingCompleted: step == .complete)
    }

    func clearPersonalizationCandidates() {
        guard let result = personalizationResult else { return }
        approvedSetupCandidateIDs = []
        deniedSetupCandidateIDs = Set(result.setupCandidates.map(\.id))
        setupApplicationReport = nil
        saveProfile(onboardingCompleted: step == .complete)
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
        saveProfile(onboardingCompleted: step == .complete)
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
        saveProfile(onboardingCompleted: step == .complete)
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
        saveProfile(onboardingCompleted: step == .complete)
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
        saveProfile(onboardingCompleted: step == .complete)
    }

    func setPersonalizationCandidateScope(id: String, role: DetourDelegationRole) {
        guard personalizationResult?.setupCandidates.contains(where: { $0.id == id }) == true else { return }
        setupCandidateScopes[id] = role
        approvedSetupCandidateIDs.insert(id)
        deniedSetupCandidateIDs.remove(id)
        setupApplicationReport = nil
        saveProfile(onboardingCompleted: step == .complete)
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
        saveProfile(onboardingCompleted: step == .complete)
        let report = await setupGraph.apply(
            result: result,
            approvedCandidateIDs: approvedSetupCandidateIDs,
            deniedCandidateIDs: deniedSetupCandidateIDs,
            setupCandidateScopes: setupCandidateScopes,
            delegationProfiles: delegationProfiles
        ) { [weak self] report in
            self?.setupApplicationReport = report
            onProgress(report)
            let completed = self?.step == .complete
            self?.saveProfile(onboardingCompleted: completed)
        }
        setupApplicationReport = report
        isApplyingSetup = false
        saveProfile(onboardingCompleted: step == .complete)
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
