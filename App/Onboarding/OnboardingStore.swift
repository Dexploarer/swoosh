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
    case complete
}

@MainActor
final class OnboardingStore: ObservableObject {
    static let defaultAgentName = "Detour"

    @Published private(set) var userName: String
    @Published private(set) var agentName: String
    @Published private(set) var step: OnboardingStep
    @Published private(set) var config: DetourConfig
    @Published private(set) var voiceRecognition: DetourVoiceRecognition
    @Published private(set) var pairingInfo: DetourPairingInfo?
    @Published private(set) var pairingError: String?
    @Published private(set) var discoveredDevices: [DetourDiscoveredDevice] = []
    @Published private(set) var storageError: String? = nil
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

    private let stateStore: DetourStateStore

    init(stateStore: DetourStateStore = DetourStateStore()) {
        self.stateStore = stateStore
        availableVoices = DetourNativeVoiceCatalog.voices()

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
            identifier: initialConfig.speech.voiceIdentifier,
            availableVoices: availableVoices
           ) {
            initialConfig.speech.voiceIdentifier = DetourNativeVoiceCatalog.defaultVoiceIdentifier()
            shouldSaveInitialConfig = true
        }
        config = initialConfig
        let initialVoiceRecognition = loadedProfile?.voiceRecognition
            ?? DetourVoiceRecognition.defaultRecognition(agentName: profileAgentName)
        voiceRecognition = initialVoiceRecognition

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
            "Scan this QR code on your device to link it to the Mac daemon."
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
             .askingDeviceSetup, .choosingDevices, .showingPairingQRCode, .complete:
            ""
        }
    }

    var canSubmitName: Bool {
        !trimmed(userNameDraft).isEmpty
    }

    var canSubmitAgentName: Bool {
        !trimmed(agentNameDraft).isEmpty
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

    func startRenamingAgent() {
        agentNameDraft = agentName.isEmpty ? Self.defaultAgentName : agentName
        step = .renamingAgent
    }

    func submitAgentName() {
        let name = trimmed(agentNameDraft)
        guard !name.isEmpty else { return }
        saveAgentName(name)
    }

    func selectVoice(identifier: String) {
        guard availableVoices.contains(where: { $0.id == identifier }) else { return }
        config.speech.voiceIdentifier = identifier
        config.updatedAt = .now
        saveConfig()
    }

    func confirmVoice() {
        step = .settingWakeWord
        saveProfile(onboardingCompleted: false)
    }

    func beginVoiceRecognitionSetup() {
        voiceRecognition.enabled = true
        voiceRecognition.enrollmentPhrase = voiceEnrollmentPhrase
        step = .enrollingVoice
        saveProfile(onboardingCompleted: false)
    }

    func completeVoiceEnrollment() {
        voiceRecognition.enabled = true
        voiceRecognition.enrollmentPhrase = voiceEnrollmentPhrase
        voiceRecognition.sampleRelativePath = stateStore.voiceEnrollmentSampleRelativePath
        voiceRecognition.enrolledAt = .now
        step = .askingDeviceSetup
        saveProfile(onboardingCompleted: false)
    }

    func skipVoiceEnrollment() {
        voiceRecognition.enabled = false
        voiceRecognition.enrollmentPhrase = nil
        voiceRecognition.sampleRelativePath = nil
        voiceRecognition.enrolledAt = nil
        step = .askingDeviceSetup
        saveProfile(onboardingCompleted: false)
    }

    func submitWakeWord() {
        let wakeWord = trimmed(wakeWordDraft)
        voiceRecognition.wakeWord = wakeWord.isEmpty ? defaultWakeWord : wakeWord
        wakeWordDraft = voiceRecognition.wakeWord
        step = .askingVoiceRecognition
        saveProfile(onboardingCompleted: false)
    }

    func setWantsOtherAppleDevices(_ wantsDevices: Bool) {
        wantsOtherAppleDevices = wantsDevices
        if wantsDevices {
            step = .choosingDevices
            saveProfile(onboardingCompleted: false)
        } else {
            step = .complete
            saveProfile(onboardingCompleted: true)
        }
    }

    func toggleDevice(_ device: DetourDeviceKind) {
        if selectedDeviceKinds.contains(device) {
            selectedDeviceKinds.remove(device)
        } else {
            selectedDeviceKinds.insert(device)
        }
        saveProfile(onboardingCompleted: false)
    }

    func mergeDiscoveredDevices(_ devices: [DetourDiscoveredDevice]) {
        let uniqueDevices = devices.uniquedByKindAndName()
        discoveredDevices = uniqueDevices
        guard !uniqueDevices.isEmpty else { return }

        var changed = false
        for device in uniqueDevices where !selectedDeviceKinds.contains(device.kind) {
            selectedDeviceKinds.insert(device.kind)
            changed = true
        }

        if step == .askingDeviceSetup && changed {
            wantsOtherAppleDevices = true
            step = .choosingDevices
        }

        if changed {
            saveProfile(onboardingCompleted: false)
        }
    }

    func title(for device: DetourDeviceKind) -> String {
        let names = discoveredDevices
            .filter { $0.kind == device }
            .map(\.name)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if names.count == 1 {
            return names[0]
        }
        if names.count > 1 {
            return "\(device.displayName) (\(names.count))"
        }
        return device.displayName
    }

    func continueToPairingQRCode() {
        wantsOtherAppleDevices = true
        saveProfile(onboardingCompleted: false)
        do {
            pairingInfo = try DetourPairingSupport.pairingInfo()
            pairingError = nil
            step = .showingPairingQRCode
            saveProfile(onboardingCompleted: false)
        } catch {
            pairingInfo = nil
            pairingError = error.localizedDescription
        }
    }

    func finishCurrentDeviceSetup() {
        pairingInfo = nil
        pairingError = nil
        wantsOtherAppleDevices = nil
        step = .askingDeviceSetup
        saveProfile(onboardingCompleted: false)
    }

    func completeDeviceSetup() {
        step = .complete
        saveProfile(onboardingCompleted: true)
    }

    var selectedVoiceIdentifier: String? {
        config.speech.voiceIdentifier
    }

    var selectedVoiceName: String {
        availableVoices.first { $0.id == selectedVoiceIdentifier }?.name ?? "System Voice"
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

    private func saveAgentName(_ name: String) {
        agentName = name
        step = .settingWakeWord
        saveProfile(onboardingCompleted: false)
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shouldRepairOnboardingVoice(
        identifier: String?,
        availableVoices: [DetourNativeVoice]
    ) -> Bool {
        guard let identifier,
              let voice = availableVoices.first(where: { $0.id == identifier }) else {
            return true
        }
        return voice.isNoveltyVoice
    }

    private func saveProfile(onboardingCompleted: Bool) {
        do {
            try stateStore.saveProfile(
                DetourProfile(
                    userName: userName,
                    agentName: agentName.isEmpty ? nil : agentName,
                    onboardingStage: Self.persistedStage(from: step),
                    onboardingCompleted: onboardingCompleted,
                    wantsOtherAppleDevices: wantsOtherAppleDevices,
                    voiceRecognition: voiceRecognition,
                    selectedDeviceKinds: availableDeviceKinds.filter { selectedDeviceKinds.contains($0) },
                    remoteInstances: remoteInstancesForPersistence()
                )
            )
            storageError = nil
        } catch {
            storageError = error.localizedDescription
        }
    }

    private func saveConfig() {
        do {
            try stateStore.saveConfig(config)
            storageError = nil
        } catch {
            storageError = error.localizedDescription
        }
    }

    private func remoteInstancesForPersistence() -> [DetourRemoteInstance] {
        guard selectedDeviceKinds.contains(.remoteDetour) else { return [] }

        let host = trimmed(remoteHostDraft)
        guard !host.isEmpty else { return [] }

        let user = trimmed(remoteUserDraft)
        let port = Int(trimmed(remotePortDraft)) ?? 22
        return [DetourRemoteInstance(host: host, sshUser: user, sshPort: port)]
    }

    private static func step(from stage: PersistedOnboardingStage) -> OnboardingStep {
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
        case .complete:
            .complete
        }
    }

    private static func persistedStage(from step: OnboardingStep) -> PersistedOnboardingStage {
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
        case .complete:
            .complete
        }
    }
}

private extension Array where Element == DetourDiscoveredDevice {
    func uniquedByKindAndName() -> [DetourDiscoveredDevice] {
        var seen = Set<String>()
        return filter { device in
            let key = "\(device.kind.rawValue):\(device.name)"
            return seen.insert(key).inserted
        }
    }
}
