// OnboardingStorePairingPersistence.swift — onboarding state extension (0.5A)

import Foundation

@MainActor
extension OnboardingStore {

    func handlePairingEvent(_ event: DetourPairingEvent) {
        pairedDeviceName = event.deviceName
        if let setupBundle = event.setupBundle {
            importSetupTransferBundle(setupBundle)
        }
        pairingError = nil
        selectedDeviceKinds.insert(kind(forPairedPlatform: event.platform))
        saveProfile(onboardingCompleted: false)
        Task { @MainActor [weak self, deviceName = event.deviceName] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self,
                  step == .showingPairingQRCode,
                  pairedDeviceName == deviceName else {
                return
            }
            pairingInfo = nil
            step = .askingPersonalizationScan
            saveProfile(onboardingCompleted: false)
        }
    }

    func setupTransferBundle(onboardingCompleted: Bool) -> DetourSetupTransferBundle {
        DetourSetupTransferBundle(
            schemaVersion: 1,
            sourcePlatform: "macOS",
            userName: userName,
            agentName: agentName.isEmpty ? Self.defaultAgentName : agentName,
            speechVoiceIdentifier: config.speech.voiceIdentifier,
            speechRateMultiplier: config.speech.rateMultiplier,
            speechPitchMultiplier: config.speech.pitchMultiplier,
            voiceRecognition: DetourSetupTransferBundle.VoiceRecognition(
                enabled: voiceRecognition.enabled,
                wakeWord: voiceRecognition.wakeWord,
                enrollmentPhrase: voiceRecognition.enrollmentPhrase,
                enrolledAt: voiceRecognition.enrolledAt
            ),
            credentialInheritance: DetourSetupTransferBundle.CredentialInheritance(
                keychainCredentials: credentialInheritanceConsent.keychainCredentials,
                browserCookies: credentialInheritanceConsent.browserCookies,
                appUsage: credentialInheritanceConsent.appUsage,
                gitHistory: credentialInheritanceConsent.gitHistory,
                contacts: credentialInheritanceConsent.contacts,
                messages: credentialInheritanceConsent.messages,
                accountDelegation: credentialInheritanceConsent.accountDelegation
            ),
            approvedSetupCandidateIDs: Array(approvedSetupCandidateIDs).sorted(),
            deniedSetupCandidateIDs: Array(deniedSetupCandidateIDs).sorted(),
            setupCandidateScopes: setupCandidateScopes.mapValues(\.rawValue),
            delegationProfiles: delegationProfiles.map {
                DetourSetupTransferBundle.DelegationProfile(
                    role: $0.role.rawValue,
                    displayName: $0.displayName,
                    accountLabels: $0.accountLabels,
                    context: $0.context
                )
            },
            selectedDeviceKinds: selectedDeviceKinds.map(\.rawValue).sorted(),
            wantsOtherAppleDevices: wantsOtherAppleDevices,
            onboardingCompleted: onboardingCompleted,
            exportedAt: .now
        )
    }

    func importSetupTransferBundle(_ bundle: DetourSetupTransferBundle) {
        let importedUserName = trimmed(bundle.userName)
        if !importedUserName.isEmpty {
            userName = importedUserName
            userNameDraft = importedUserName
        }
        if let importedAgentName = bundle.agentName.map(trimmed), !importedAgentName.isEmpty {
            agentName = importedAgentName
            agentNameDraft = importedAgentName
        }
        if let voiceID = bundle.speechVoiceIdentifier,
           voiceID == DetourVoiceIdentifier.omniVoiceLocal {
            config.speech.voiceIdentifier = voiceID
        }
        config.speech.rateMultiplier = bundle.speechRateMultiplier
        config.speech.pitchMultiplier = bundle.speechPitchMultiplier
        config.updatedAt = .now
        voiceRecognition.enabled = bundle.voiceRecognition.enabled
        voiceRecognition.wakeWord = bundle.voiceRecognition.wakeWord
        voiceRecognition.enrollmentPhrase = bundle.voiceRecognition.enrollmentPhrase
        voiceRecognition.enrolledAt = bundle.voiceRecognition.enrolledAt
        wakeWordDraft = voiceRecognition.wakeWord
        credentialInheritanceConsent = DetourCredentialInheritanceConsent(
            keychainCredentials: bundle.credentialInheritance.keychainCredentials,
            browserCookies: bundle.credentialInheritance.browserCookies,
            appUsage: bundle.credentialInheritance.appUsage,
            gitHistory: bundle.credentialInheritance.gitHistory,
            contacts: bundle.credentialInheritance.contacts,
            messages: bundle.credentialInheritance.messages,
            accountDelegation: bundle.credentialInheritance.accountDelegation
        )
        approvedSetupCandidateIDs = Set(bundle.approvedSetupCandidateIDs)
        deniedSetupCandidateIDs = Set(bundle.deniedSetupCandidateIDs)
        setupCandidateScopes = (bundle.setupCandidateScopes ?? [:]).compactMapValues(DetourDelegationRole.init(rawValue:))
        delegationProfiles = bundle.delegationProfiles.compactMap { profile in
            guard let role = DetourDelegationRole(rawValue: profile.role) else { return nil }
            return DetourDelegationProfile(
                role: role,
                displayName: profile.displayName,
                accountLabels: profile.accountLabels,
                context: profile.context
            )
        }
        selectedDeviceKinds.formUnion(bundle.selectedDeviceKinds.compactMap(DetourDeviceKind.init(rawValue:)))
        wantsOtherAppleDevices = bundle.wantsOtherAppleDevices
        saveConfig()
    }

    func kind(forPairedPlatform platform: String) -> DetourDeviceKind {
        let value = platform.lowercased()
        if value.contains("ipad") { return .iPad }
        if value.contains("watch") { return .appleWatch }
        if value.contains("vision") { return .visionPro }
        if value.contains("mac") { return .macBook }
        return .iPhone
    }

    var selectedVoiceIdentifier: String? {
        config.speech.voiceIdentifier
    }

    var selectedVoiceName: String {
        "OmniVoice local"
    }

    var voicePreviewText: String {
        "Hello \(userName), I'm \(agentName)."
    }

    var voiceEnrollmentPhrase: String {
        "\(voiceRecognition.wakeWord), it's \(userName)."
    }

    var defaultWakeWord: String {
        "Hey \(agentName)"
    }

    func voiceEnrollmentSampleURL() throws -> URL {
        try stateStore.prepareDirectories()
        return stateStore.voiceEnrollmentSampleURL
    }

    func saveAgentName(_ name: String) {
        agentName = name
        step = .settingWakeWord
        saveProfile(onboardingCompleted: false)
    }

    func restoreSavedPersonalizationReportIfNeeded() {
        guard personalizationResult == nil,
              step == .reviewingPersonalizationScan || step == .complete else {
            return
        }
        do {
            guard let result = try stateStore.loadPersonalizationReport() else {
                if step == .reviewingPersonalizationScan {
                    step = .askingPersonalizationScan
                }
                return
            }
            personalizationResult = result
            if approvedSetupCandidateIDs.isEmpty && deniedSetupCandidateIDs.isEmpty {
                approvedSetupCandidateIDs = Set(result.setupCandidates.filter(\.selected).map(\.id))
                deniedSetupCandidateIDs = Set(result.setupCandidates.filter { !$0.selected }.map(\.id))
            }
            let defaultScopes = defaultSetupCandidateScopes(result.setupCandidates)
            if setupCandidateScopes.isEmpty || shouldResetStalePersonalizationScopes(defaultScopes) {
                setupCandidateScopes = defaultScopes
            }
            if delegationProfiles.isEmpty {
                delegationProfiles = result.delegationProfiles
            }
            personalizationProgress = .complete
        } catch {
            storageError = error.localizedDescription
            if step == .reviewingPersonalizationScan {
                step = .askingPersonalizationScan
            }
        }
    }

    func shouldResetStalePersonalizationScopes(_ defaultScopes: [String: DetourDelegationRole]) -> Bool {
        guard step == .reviewingPersonalizationScan else { return false }
        let agentDefaultIDs = defaultScopes
            .filter { $0.value == .agent }
            .map(\.key)
        guard agentDefaultIDs.count >= 2 else { return false }
        return agentDefaultIDs.allSatisfy { setupCandidateScopes[$0] == .user }
    }

    func completeOnboarding() {
        step = .complete
        saveProfile(onboardingCompleted: true)
    }

    var previousStep: OnboardingStep? {
        switch step {
        case .askingName:
            nil
        case .askingAgentName:
            .askingName
        case .renamingAgent:
            .askingAgentName
        case .choosingVoice:
            .askingAgentName
        case .settingWakeWord:
            .askingAgentName
        case .askingVoiceRecognition:
            .settingWakeWord
        case .enrollingVoice:
            .askingVoiceRecognition
        case .askingDeviceSetup:
            .askingVoiceRecognition
        case .choosingDevices:
            .askingDeviceSetup
        case .showingPairingQRCode:
            .choosingDevices
        case .askingPersonalizationScan:
            wantsOtherAppleDevices == true ? .choosingDevices : .askingDeviceSetup
        case .askingCredentialInheritance:
            .askingPersonalizationScan
        case .runningPersonalizationScan:
            nil
        case .reviewingPersonalizationScan:
            .askingCredentialInheritance
        case .complete:
            personalizationResult == nil ? .askingPersonalizationScan : .reviewingPersonalizationScan
        }
    }

    func section(_ title: String, _ body: String) -> String {
        body.isEmpty ? "" : "\(title)\n\(body)"
    }

    func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func shouldRepairOnboardingVoice(
        identifier: String?
    ) -> Bool {
        identifier != DetourVoiceIdentifier.omniVoiceLocal
    }

    func saveProfile(onboardingCompleted: Bool) {
        do {
            let existing = try? stateStore.loadProfile()
            let completed = onboardingCompleted
                || step == .complete
                || existing?.onboardingCompleted == true
                || existing?.onboardingStage == .complete
            try stateStore.saveProfile(
                DetourProfile(
                    userName: userName,
                    agentName: agentName.isEmpty ? nil : agentName,
                    onboardingStage: completed ? .complete : Self.persistedStage(from: step),
                    onboardingCompleted: completed,
                    wantsOtherAppleDevices: wantsOtherAppleDevices,
                    voiceRecognition: voiceRecognition,
                    credentialInheritance: credentialInheritanceConsent,
                    approvedSetupCandidateIDs: Array(approvedSetupCandidateIDs).sorted(),
                    deniedSetupCandidateIDs: Array(deniedSetupCandidateIDs).sorted(),
                    setupCandidateScopes: setupCandidateScopes,
                    delegationProfiles: delegationProfiles,
                    selectedDeviceKinds: availableDeviceKinds.filter { selectedDeviceKinds.contains($0) },
                    remoteInstances: remoteInstancesForPersistence()
                )
            )
            storageError = nil
        } catch {
            storageError = error.localizedDescription
        }
    }

    func saveConfig() {
        do {
            try stateStore.saveConfig(config)
            storageError = nil
        } catch {
            storageError = error.localizedDescription
        }
    }

    func remoteInstancesForPersistence() -> [DetourRemoteInstance] {
        guard selectedDeviceKinds.contains(.remoteDetour) else { return [] }

        let host = trimmed(remoteHostDraft)
        guard !host.isEmpty else { return [] }

        let user = trimmed(remoteUserDraft)
        let port = Int(trimmed(remotePortDraft)) ?? 22
        return [DetourRemoteInstance(host: host, sshUser: user, sshPort: port)]
    }

    static func step(from stage: PersistedOnboardingStage) -> OnboardingStep {
        switch stage {
        case .askingName:
            .askingName
        case .askingAgentName:
            .askingAgentName
        case .renamingAgent:
            .renamingAgent
        case .choosingVoice:
            .settingWakeWord
        case .askingVoiceRecognition:
            .askingVoiceRecognition
        case .enrollingVoice:
            .enrollingVoice
        case .settingWakeWord:
            .settingWakeWord
        case .askingDeviceSetup:
            .askingDeviceSetup
        case .choosingDevices:
            .choosingDevices
        case .showingPairingQRCode:
            .showingPairingQRCode
        case .askingPersonalizationScan:
            .askingPersonalizationScan
        case .askingCredentialInheritance:
            .askingCredentialInheritance
        case .runningPersonalizationScan:
            .askingPersonalizationScan
        case .reviewingPersonalizationScan:
            .reviewingPersonalizationScan
        case .askingPersonalizationQuestion:
            .reviewingPersonalizationScan
        case .complete:
            .complete
        }
    }

    static func persistedStage(from step: OnboardingStep) -> PersistedOnboardingStage {
        switch step {
        case .askingName:
            .askingName
        case .askingAgentName:
            .askingAgentName
        case .renamingAgent:
            .renamingAgent
        case .choosingVoice:
            .settingWakeWord
        case .askingVoiceRecognition:
            .askingVoiceRecognition
        case .enrollingVoice:
            .enrollingVoice
        case .settingWakeWord:
            .settingWakeWord
        case .askingDeviceSetup:
            .askingDeviceSetup
        case .choosingDevices:
            .choosingDevices
        case .showingPairingQRCode:
            .showingPairingQRCode
        case .askingPersonalizationScan:
            .askingPersonalizationScan
        case .askingCredentialInheritance:
            .askingCredentialInheritance
        case .runningPersonalizationScan:
            .runningPersonalizationScan
        case .reviewingPersonalizationScan:
            .reviewingPersonalizationScan
        case .complete:
            .complete
        }
    }
}
