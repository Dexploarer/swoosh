// OnboardingStore.swift — persisted deterministic Detour intro state (0.5A)

import Foundation

enum OnboardingStep: Equatable {
    case askingName
    case askingAgentName
    case renamingAgent
    case choosingVoice
    case askingVoiceRecognition
    case enrollingVoice
    case settingWakeWord
    case askingDeviceSetup
    case choosingDevices
    case showingPairingQRCode
    case askingPersonalizationScan
    case askingCredentialInheritance
    case runningPersonalizationScan
    case reviewingPersonalizationScan
    case complete
}

@MainActor
final class OnboardingStore: ObservableObject {
    static let defaultAgentName = "Detour"

    @Published var userName: String
    @Published var agentName: String
    @Published var step: OnboardingStep
    @Published var config: DetourConfig
    @Published var voiceRecognition: DetourVoiceRecognition
    @Published var pairingInfo: DetourPairingInfo?
    @Published var pairingError: String?
    @Published var pairedDeviceName: String?
    @Published var discoveredDevices: [DetourDiscoveredDevice] = []
    @Published var personalizationProgress = DetourPersonalizationProgress.idle
    @Published var personalizationResult: DetourPersonalizationScanResult?
    @Published var credentialInheritanceConsent: DetourCredentialInheritanceConsent
    @Published var approvedSetupCandidateIDs: Set<String>
    @Published var deniedSetupCandidateIDs: Set<String>
    @Published var setupCandidateScopes: [String: DetourDelegationRole]
    @Published var setupApplicationReport: DetourSetupApplicationReport?
    @Published var isApplyingSetup = false
    @Published var delegationProfiles: [DetourDelegationProfile]
    @Published var storageError: String? = nil
    @Published var userNameDraft: String
    @Published var agentNameDraft: String
    @Published var wakeWordDraft: String
    @Published var selectedDeviceKinds: Set<DetourDeviceKind>
    @Published var wantsOtherAppleDevices: Bool?
    @Published var remoteHostDraft: String
    @Published var remoteUserDraft: String
    @Published var remotePortDraft: String
    let availableVoices: [DetourNativeVoice]
    let availableDeviceKinds = DetourDeviceKind.allCases

    let stateStore: DetourStateStore
    let setupGraph: DetourPersonalizationSetupGraph

    init(
        stateStore: DetourStateStore = DetourStateStore(),
        setupGraph: DetourPersonalizationSetupGraph = DetourPersonalizationSetupGraph()
    ) {
        self.stateStore = stateStore
        self.setupGraph = setupGraph
        availableVoices = []

        var loadedProfile: DetourProfile?
        var loadedConfig: DetourConfig?
        var initialStorageError: String?

        do {
            try stateStore.prepareDirectories()
            loadedProfile = try stateStore.loadProfile()
            loadedConfig = try stateStore.loadConfig()
        } catch {
            initialStorageError = error.localizedDescription
        }

        let persistedUserName = loadedProfile?.userName ?? ""
        let persistedAgentName = loadedProfile?.agentName ?? ""
        let profileAgentName = persistedAgentName.isEmpty ? Self.defaultAgentName : persistedAgentName
        var initialConfig = loadedConfig ?? DetourConfig.defaultConfig()
        var shouldSaveInitialConfig = loadedConfig == nil
        if loadedProfile?.onboardingCompleted != true,
           Self.shouldRepairOnboardingVoice(
            identifier: initialConfig.speech.voiceIdentifier
           ) {
            initialConfig.speech.voiceIdentifier = DetourVoiceIdentifier.omniVoiceLocal
            shouldSaveInitialConfig = true
        }
        config = initialConfig
        let initialVoiceRecognition = loadedProfile?.voiceRecognition
            ?? DetourVoiceRecognition.defaultRecognition(agentName: profileAgentName)
        voiceRecognition = initialVoiceRecognition
        credentialInheritanceConsent = loadedProfile?.credentialInheritance ?? DetourCredentialInheritanceConsent()
        approvedSetupCandidateIDs = Set(loadedProfile?.approvedSetupCandidateIDs ?? [])
        deniedSetupCandidateIDs = Set(loadedProfile?.deniedSetupCandidateIDs ?? [])
        setupCandidateScopes = loadedProfile?.setupCandidateScopes ?? [:]
        delegationProfiles = loadedProfile?.delegationProfiles ?? []

        userName = persistedUserName
        agentName = persistedAgentName
        userNameDraft = persistedUserName
        agentNameDraft = profileAgentName
        wakeWordDraft = initialVoiceRecognition.wakeWord
        selectedDeviceKinds = Set(loadedProfile?.selectedDeviceKinds ?? [])
        wantsOtherAppleDevices = loadedProfile?.wantsOtherAppleDevices
        let remoteInstance = loadedProfile?.remoteInstances.first
        remoteHostDraft = remoteInstance?.host ?? ""
        remoteUserDraft = remoteInstance?.sshUser ?? NSUserName()
        remotePortDraft = remoteInstance.map { String($0.sshPort) } ?? "22"
        storageError = initialStorageError

        if persistedUserName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            step = .askingName
        } else if persistedAgentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            step = .askingAgentName
        } else if loadedProfile?.onboardingCompleted == true {
            step = .complete
        } else {
            step = Self.step(from: loadedProfile?.onboardingStage ?? .choosingVoice)
        }
        restoreSavedPersonalizationReportIfNeeded()

        if shouldSaveInitialConfig && initialStorageError == nil {
            saveConfig()
        }
    }

    var promptText: String {
        switch step {
        case .askingName:
            "Hello, you made a Detour, to guide you on the rest of your journey, can i know your name?"
        case .askingAgentName:
            "Thank you, \(userName). Keep the name Detour, or change it?"
        case .renamingAgent:
            "What would you like to call me, \(userName)?"
        case .choosingVoice:
            "What should \(agentName) sound like?"
        case .askingVoiceRecognition:
            "Should \(agentName) learn your voice so it knows when it's you?"
        case .enrollingVoice:
            "Say this phrase so \(agentName) can learn your voice: \(voiceEnrollmentPhrase)"
        case .settingWakeWord:
            "What wake word should \(agentName) listen for?"
        case .askingDeviceSetup:
            selectedDeviceKinds.isEmpty
                ? "Any other Apple devices or remote Detours?"
                : "Any more Apple devices or remote Detours?"
        case .choosingDevices:
            "Which Apple devices or remote Detours should \(agentName) connect to next?"
        case .showingPairingQRCode:
            "Scan this QR code. \(agentName) will continue when the device connects."
        case .askingPersonalizationScan:
            "Want \(agentName) to scan this Mac and learn your setup?"
        case .askingCredentialInheritance:
            "Let \(agentName) read local apps, Git history, Contacts, Messages, Keychain, and browser auth?"
        case .runningPersonalizationScan:
            "\(agentName) is learning your setup."
        case .reviewingPersonalizationScan:
            "Here is what \(agentName) found."
        case .complete:
            "Nice to meet you, \(userName). I'm \(agentName)."
        }
    }

    var primaryActionTitle: String {
        switch step {
        case .askingName:
            "Continue"
        case .renamingAgent:
            "Save name"
        case .askingAgentName, .choosingVoice, .askingVoiceRecognition, .enrollingVoice, .settingWakeWord,
             .askingDeviceSetup, .choosingDevices, .showingPairingQRCode, .askingPersonalizationScan,
             .askingCredentialInheritance, .runningPersonalizationScan, .reviewingPersonalizationScan, .complete:
            ""
        }
    }

    var canSubmitName: Bool {
        !trimmed(userNameDraft).isEmpty
    }

    var canSubmitAgentName: Bool {
        !trimmed(agentNameDraft).isEmpty
    }

    var canGoBack: Bool {
        previousStep != nil
    }

    func goBack() {
        switch step {
        case .showingPairingQRCode:
            pairingInfo = nil
            pairingError = nil
            pairedDeviceName = nil
            step = .choosingDevices
        case .runningPersonalizationScan:
            return
        default:
            guard let previousStep else { return }
            step = previousStep
        }

        if step == .askingName {
            userNameDraft = userName
        }
        if step == .askingAgentName {
            agentNameDraft = agentName.isEmpty ? Self.defaultAgentName : agentName
        }
        if step == .settingWakeWord {
            wakeWordDraft = voiceRecognition.wakeWord
        }
        if step == .askingCredentialInheritance {
            personalizationProgress = .idle
        }
        saveProfile(onboardingCompleted: false)
    }

    func submitName() {
        let name = trimmed(userNameDraft)
        guard !name.isEmpty else { return }
        userName = name
        agentNameDraft = ""
        step = .askingAgentName
        saveProfile(onboardingCompleted: false)
    }

    func submitAgentDecision() {
        let name = trimmed(agentNameDraft)
        if name.isEmpty {
            acceptDefaultAgentName()
        } else {
            saveAgentName(name)
        }
    }

    func acceptDefaultAgentName() {
        saveAgentName(Self.defaultAgentName)
    }

}
