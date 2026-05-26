// OnboardingStoreVoiceDevices.swift — onboarding state extension (0.5A)

import Foundation

@MainActor
extension OnboardingStore {
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
        guard identifier == DetourVoiceIdentifier.omniVoiceLocal else { return }
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
            step = .askingPersonalizationScan
            saveProfile(onboardingCompleted: false)
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
            DetourPairingWebServer.shared.onDevicePaired = { [weak self] event in
                Task { @MainActor in
                    self?.handlePairingEvent(event)
                }
            }
            pairingInfo = try DetourPairingSupport.pairingInfo(setupBundle: setupTransferBundle(onboardingCompleted: false))
            pairingError = nil
            pairedDeviceName = nil
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
        pairedDeviceName = nil
        wantsOtherAppleDevices = nil
        step = .askingDeviceSetup
        saveProfile(onboardingCompleted: false)
    }
}
