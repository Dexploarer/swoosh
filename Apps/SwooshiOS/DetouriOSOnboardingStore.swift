// DetouriOSOnboardingStore.swift — deterministic iPhone onboarding flow (0.5A)

import AVFoundation
import Foundation

@MainActor
final class DetouriOSOnboardingStore: ObservableObject {
    static let defaultAgentName = "Detour"

    @Published private(set) var userName: String
    @Published private(set) var agentName: String
    @Published private(set) var step: DetouriOSOnboardingStep
    @Published private(set) var config: DetouriOSConfig
    @Published private(set) var voiceRecognition: DetouriOSVoiceRecognition
    @Published private(set) var pairedMac: DetouriOSPairedMac?
    @Published private(set) var pairingError: String?
    @Published private(set) var storageError: String?
    @Published var userNameDraft: String
    @Published var agentNameDraft: String
    @Published var wakeWordDraft: String
    @Published var selectedDeviceKinds: Set<DetouriOSDeviceKind>
    @Published var wantsOtherAppleDevices: Bool?
    @Published var remoteHostDraft: String
    @Published var remoteUserDraft: String
    @Published var remotePortDraft: String
    @Published private(set) var availableVoices: [DetouriOSVoice]
    @Published private(set) var personalVoiceAuthorizationStatus: AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus

    let availableDeviceKinds = DetouriOSDeviceKind.allCases

    private let stateStore: DetouriOSStateStore
    private var voiceChangeObserver: NSObjectProtocol?

    init(stateStore: DetouriOSStateStore = DetouriOSStateStore()) {
        self.stateStore = stateStore
        let initialAvailableVoices = DetouriOSVoiceCatalog.voices()
        availableVoices = initialAvailableVoices
        personalVoiceAuthorizationStatus = AVSpeechSynthesizer.personalVoiceAuthorizationStatus

        var loadedProfile: DetouriOSProfile?
        var loadedConfig: DetouriOSConfig?
        var initialStorageError: String?

        do {
            try stateStore.prepareDirectories()
            loadedProfile = try stateStore.loadProfile()
            loadedConfig = try stateStore.loadConfig()
        } catch {
            initialStorageError = error.localizedDescription
        }

        let loadedUserName = loadedProfile?.userName ?? ""
        let persistedUserName = Self.isAllowedHumanName(loadedUserName) ? loadedUserName : ""
        let loadedAgentName = loadedProfile?.agentName ?? ""
        let persistedAgentName = Self.namesMatch(loadedAgentName, persistedUserName) ? "" : loadedAgentName
        let profileAgentName = persistedAgentName.isEmpty ? Self.defaultAgentName : persistedAgentName
        var initialConfig = loadedConfig ?? DetouriOSConfig.defaultConfig()
        var shouldSaveInitialConfig = loadedConfig == nil
        if loadedProfile?.onboardingCompleted != true,
           Self.shouldRepairOnboardingVoice(
            identifier: initialConfig.speech.voiceIdentifier,
            availableVoices: initialAvailableVoices
           ) {
            initialConfig.speech.voiceIdentifier = DetouriOSVoiceCatalog.defaultVoiceIdentifier()
            shouldSaveInitialConfig = true
        }
        DetouriOSVoiceSettings.useDefaultLocalVoice()

        let initialVoiceRecognition = loadedProfile?.voiceRecognition
            ?? DetouriOSVoiceRecognition.defaultRecognition(agentName: profileAgentName)
        config = initialConfig
        voiceRecognition = initialVoiceRecognition
        userName = persistedUserName
        agentName = persistedAgentName
        pairedMac = loadedProfile?.pairedMac
        userNameDraft = persistedUserName
        agentNameDraft = profileAgentName
        wakeWordDraft = initialVoiceRecognition.wakeWord
        selectedDeviceKinds = Set(loadedProfile?.selectedDeviceKinds ?? [])
        wantsOtherAppleDevices = loadedProfile?.wantsOtherAppleDevices
        let remoteInstance = loadedProfile?.remoteInstances.first
        remoteHostDraft = remoteInstance?.host ?? ""
        remoteUserDraft = remoteInstance?.sshUser ?? ""
        remotePortDraft = remoteInstance.map { String($0.sshPort) } ?? "22"
        storageError = initialStorageError

        if persistedUserName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            step = .askingName
        } else if persistedAgentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            step = .askingAgentName
        } else if loadedProfile?.onboardingCompleted == true {
            step = .complete
        } else {
            step = loadedProfile?.onboardingStage ?? .choosingVoice
        }
        if step == .choosingVoice && !hasRealVoiceChoice {
            step = .settingWakeWord
        }

        if shouldSaveInitialConfig && initialStorageError == nil {
            saveConfig()
        }

        voiceChangeObserver = NotificationCenter.default.addObserver(
            forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAvailableVoices()
            }
        }
    }

    var promptText: String {
        fallbackPromptText
    }

    var promptRequestIdentity: String {
        [
            step.rawValue,
            userName,
            resolvedAgentName,
            voiceRecognition.wakeWord,
            voiceEnrollmentPhrase
        ].joined(separator: "|")
    }

    func resolvePromptText() -> String {
        fallbackPromptText
    }

    private var fallbackPromptText: String {
        switch step {
        case .askingName:
            "What's your name?"
        case .askingAgentName:
            "Keep the name Detour?"
        case .renamingAgent:
            "What would you like to call me, \(userName)?"
        case .choosingVoice:
            "What should \(resolvedAgentName) sound like?"
        case .settingWakeWord:
            "What wake word should \(resolvedAgentName) listen for?"
        case .askingVoiceRecognition:
            "Should \(resolvedAgentName) learn your voice so it knows when it's you?"
        case .enrollingVoice:
            "Say this phrase so \(resolvedAgentName) can learn your voice: \(voiceEnrollmentPhrase)"
        case .askingDeviceSetup:
            "Do you have any other Apple devices or remote Detours you'd like \(resolvedAgentName) set up on?"
        case .choosingDevices:
            "Which Apple devices or remote Detours should \(resolvedAgentName) connect to next?"
        case .complete:
            "Nice to meet you, \(userName). I'm \(resolvedAgentName)."
        }
    }

    var canSubmitName: Bool {
        Self.isAllowedHumanName(trimmed(userNameDraft))
    }

    var canSubmitAgentName: Bool {
        let name = trimmed(agentNameDraft)
        return !name.isEmpty && !Self.namesMatch(name, userName)
    }

    var selectedVoiceIdentifier: String? {
        config.speech.voiceIdentifier
    }

    var selectedVoiceName: String {
        availableVoices.first { $0.id == selectedVoiceIdentifier }?.name ?? "System Voice"
    }

    var voiceChoices: [DetouriOSVoice] {
        let bestVoices = availableVoices.filter(\.isBestSystemVoice)
        let choices = bestVoices.isEmpty ? availableVoices : bestVoices
        return Array(choices.prefix(6))
    }

    var hasRealVoiceChoice: Bool {
        DetouriOSSpeechService.canInstallKokoroAssets
            || DetouriOSSpeechService.hasCachedKokoroAssets()
            || voiceChoices.count > 1
            || hasPersonalVoice
    }

    var hasBestSystemVoice: Bool {
        availableVoices.contains(where: \.isBestSystemVoice)
    }

    var hasPersonalVoice: Bool {
        availableVoices.contains(where: \.isPersonalVoice)
    }

    var canRequestPersonalVoiceAccess: Bool {
        personalVoiceAuthorizationStatus == .notDetermined
    }

    var voiceQualityStatusText: String? {
        guard !availableVoices.isEmpty, !hasBestSystemVoice else { return nil }
        return "Only basic system voices are installed."
    }

    var personalVoiceSetupText: String? {
        guard !hasPersonalVoice else { return nil }
        switch personalVoiceAuthorizationStatus {
        case .notDetermined:
            return "Create Personal Voice in Accessibility, then allow app requests."
        case .denied:
            return "Turn on Allow Apps to Request to Use in Personal Voice settings."
        case .authorized:
            return "Create Personal Voice in Accessibility, then it appears here."
        case .unsupported:
            return nil
        @unknown default:
            return nil
        }
    }

    var personalVoiceAuthorizationText: String? {
        switch personalVoiceAuthorizationStatus {
        case .notDetermined:
            return "Personal Voice access is off."
        case .denied:
            return "Personal Voice access was denied."
        case .unsupported:
            return "Personal Voice is not supported on this device."
        case .authorized:
            return nil
        @unknown default:
            return nil
        }
    }

    var voicePreviewText: String {
        "Hello \(userName), I'm \(resolvedAgentName)."
    }

    var defaultWakeWord: String {
        "Hey \(resolvedAgentName)"
    }

    var voiceEnrollmentPhrase: String {
        "\(voiceRecognition.wakeWord), it's \(userName)."
    }

    var pairingStatusText: String? {
        guard let pairedMac else { return nil }
        switch pairedMac.lastReachability {
        case .unknown:
            return "Paired with \(pairedMac.host)"
        case .checking:
            return "Checking \(pairedMac.host)"
        case .reachable:
            return "Mac daemon reachable at \(pairedMac.host)"
        case .unreachable:
            return "Paired, but the Mac daemon is not reachable yet."
        }
    }

    func submitName() {
        let name = trimmed(userNameDraft)
        guard Self.isAllowedHumanName(name) else {
            userNameDraft = ""
            return
        }
        userName = name
        agentNameDraft = Self.defaultAgentName
        step = .askingAgentName
        saveProfile(onboardingCompleted: false)
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
        guard !Self.namesMatch(name, userName) else {
            agentNameDraft = Self.defaultAgentName
            return
        }
        saveAgentName(name)
    }

    func selectVoice(identifier: String) {
        guard availableVoices.contains(where: { $0.id == identifier }) else { return }
        config.speech.voiceIdentifier = identifier
        DetouriOSVoiceSettings.useDefaultLocalVoice()
        config.updatedAt = .now
        saveConfig()
    }

    func requestPersonalVoiceAccess() {
        AVSpeechSynthesizer.requestPersonalVoiceAuthorization { [weak self] status in
            Task { @MainActor in
                self?.personalVoiceAuthorizationStatus = status
                self?.refreshAvailableVoices()
            }
        }
    }

    func confirmVoice() {
        step = .settingWakeWord
        saveProfile(onboardingCompleted: false)
    }

    func submitWakeWord() {
        let wakeWord = trimmed(wakeWordDraft)
        voiceRecognition.wakeWord = wakeWord.isEmpty ? defaultWakeWord : wakeWord
        wakeWordDraft = voiceRecognition.wakeWord
        step = .askingVoiceRecognition
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

    func toggleDevice(_ device: DetouriOSDeviceKind) {
        if selectedDeviceKinds.contains(device) {
            selectedDeviceKinds.remove(device)
        } else {
            selectedDeviceKinds.insert(device)
        }
        saveProfile(onboardingCompleted: false)
    }

    func completeDeviceSetup() {
        step = .complete
        saveProfile(onboardingCompleted: true)
    }

    func voiceEnrollmentSampleURL() throws -> URL {
        try stateStore.prepareDirectories()
        return stateStore.voiceEnrollmentSampleURL
    }

    func handlePairingURL(_ url: URL) {
        do {
            let payload = try DetouriOSPairingSupport.parse(url)
            try TokenStore.save(payload.token)
            HostStore.current = payload.hostURL
            pairedMac = DetouriOSPairedMac(
                host: payload.hostURL.absoluteString,
                pairedAt: .now,
                lastReachability: .checking
            )
            selectedDeviceKinds.insert(.macBook)
            pairingError = nil
            saveProfile(onboardingCompleted: step == .complete)
        } catch {
            pairingError = error.localizedDescription
        }
    }

    func refreshPairedMacReachability() async {
        guard let hostURL = pairedMac?.hostURL else { return }
        pairedMac?.lastReachability = .checking
        saveProfile(onboardingCompleted: step == .complete)

        let client = SwooshAPIClient(baseURL: hostURL, token: TokenStore.load())
        let reachable = await client.health()
        pairedMac?.lastReachability = reachable ? .reachable : .unreachable
        saveProfile(onboardingCompleted: step == .complete)
    }

    private func saveAgentName(_ name: String) {
        let resolvedName = Self.namesMatch(name, userName) ? Self.defaultAgentName : name
        agentName = resolvedName
        wakeWordDraft = "Hey \(resolvedName)"
        voiceRecognition.wakeWord = wakeWordDraft
        step = hasRealVoiceChoice ? .choosingVoice : .settingWakeWord
        saveProfile(onboardingCompleted: false)
    }

    private var resolvedAgentName: String {
        let name = agentName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || Self.namesMatch(name, userName) ? Self.defaultAgentName : name
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isAllowedHumanName(_ value: String) -> Bool {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && !namesMatch(name, defaultAgentName)
    }

    private static func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        canonicalName(lhs) == canonicalName(rhs)
    }

    private static func canonicalName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func refreshAvailableVoices() {
        availableVoices = DetouriOSVoiceCatalog.voices()
        personalVoiceAuthorizationStatus = AVSpeechSynthesizer.personalVoiceAuthorizationStatus
        if step == .choosingVoice && !hasRealVoiceChoice {
            step = .settingWakeWord
        }
        if Self.shouldRepairOnboardingVoice(
            identifier: config.speech.voiceIdentifier,
            availableVoices: availableVoices
        ) {
            config.speech.voiceIdentifier = DetouriOSVoiceCatalog.defaultVoiceIdentifier()
            config.updatedAt = .now
            saveConfig()
        }
    }

    private static func shouldRepairOnboardingVoice(
        identifier: String?,
        availableVoices: [DetouriOSVoice]
    ) -> Bool {
        guard let identifier,
              let voice = availableVoices.first(where: { $0.id == identifier }) else {
            return true
        }
        if availableVoices.contains(where: \.isBestSystemVoice) {
            return !voice.isBestSystemVoice
        }
        return voice.isNoveltyVoice
    }

    private func saveProfile(onboardingCompleted: Bool) {
        do {
            try stateStore.saveProfile(
                DetouriOSProfile(
                    userName: userName,
                    agentName: agentName.isEmpty ? nil : agentName,
                    onboardingStage: step,
                    onboardingCompleted: onboardingCompleted,
                    wantsOtherAppleDevices: wantsOtherAppleDevices,
                    voiceRecognition: voiceRecognition,
                    selectedDeviceKinds: availableDeviceKinds.filter { selectedDeviceKinds.contains($0) },
                    remoteInstances: remoteInstancesForPersistence(),
                    pairedMac: pairedMac
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

    private func remoteInstancesForPersistence() -> [DetouriOSRemoteInstance] {
        guard selectedDeviceKinds.contains(.remoteDetour) else { return [] }

        let host = trimmed(remoteHostDraft)
        guard !host.isEmpty else { return [] }

        let user = trimmed(remoteUserDraft)
        let port = Int(trimmed(remotePortDraft)) ?? 22
        return [DetouriOSRemoteInstance(host: host, sshUser: user, sshPort: port)]
    }
}
