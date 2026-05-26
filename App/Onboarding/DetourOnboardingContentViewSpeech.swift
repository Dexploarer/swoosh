// DetourOnboardingContentViewSpeech.swift — Detour onboarding view slice (0.5A)

import AppKit
import QuartzCore

extension DetourOnboardingContentView {
    func beginLiveSpeechCapture(stopCurrentSpeech: Bool) async {
        guard stepAllowsLiveSpeech, !liveSpeech.isListening else { return }
        guard await liveSpeech.requestAuthorization() == .authorized else { return }
        if stopCurrentSpeech {
            speech.stop()
        }
        lastHandledFinalVoiceInput = ""
        try? await liveSpeech.start()
    }

    var stepAllowsLiveSpeech: Bool {
        switch store.step {
        case .runningPersonalizationScan, .complete:
            false
        case .askingName, .askingAgentName, .renamingAgent, .choosingVoice, .askingVoiceRecognition,
             .enrollingVoice, .settingWakeWord, .askingDeviceSetup, .choosingDevices, .showingPairingQRCode,
             .askingPersonalizationScan, .askingCredentialInheritance, .reviewingPersonalizationScan:
            true
        }
    }

    func applyPartialVoiceInput(_ transcript: String) {
        guard liveSpeech.isListening, acceptsLiveSpeechInput else { return }
        let value = cleanedSpokenValue(transcript)
        guard !value.isEmpty else { return }
        guard !isCurrentPromptEcho(value) else { return }

        switch store.step {
        case .askingName:
            let name = cleanName(spokenValue(value, dropping: ["my name is", "my name's", "i'm", "i am", "this is", "it is", "it's", "its"]))
            store.userNameDraft = name
            inputField.stringValue = name
        case .renamingAgent:
            if let candidate = spokenAgentNameCandidate(value, allowBareName: true) {
                store.agentNameDraft = candidate
                inputField.stringValue = candidate
            }
        case .settingWakeWord:
            let wakeWord = spokenValue(value, dropping: ["wake word is", "the wake word is", "listen for"])
            store.wakeWordDraft = wakeWord
            inputField.stringValue = wakeWord
        case .choosingDevices:
            applyRemoteDrafts(from: value)
        case .askingAgentName, .choosingVoice, .askingVoiceRecognition, .enrollingVoice,
             .askingDeviceSetup, .showingPairingQRCode, .askingPersonalizationScan,
             .askingCredentialInheritance, .runningPersonalizationScan, .reviewingPersonalizationScan,
             .complete:
            break
        }
    }

    func handleFinalVoiceInput(_ transcript: String) {
        guard acceptsLiveSpeechInput else { return }
        let value = cleanedSpokenValue(transcript)
        guard !value.isEmpty, consumeFinalVoiceInput(value) else { return }
        let command = value.lowercased()
        guard !isCurrentPromptEcho(command) else { return }
        if isBackCommand(command), store.canGoBack {
            goBackFromUI()
            return
        }

        switch store.step {
        case .askingName:
            if isContinueCommand(command), !store.userNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                liveSpeech.cancel()
                store.submitName()
                startPrompt()
            } else {
                let name = cleanName(spokenValue(value, dropping: ["my name is", "my name's", "i'm", "i am", "this is", "it is", "it's", "its"]))
                guard !name.isEmpty, !isContinueCommand(command) else { return }
                store.userNameDraft = name
                inputField.stringValue = name
                liveSpeech.cancel()
                store.submitName()
                startPrompt()
            }
        case .askingAgentName:
            if isAffirmative(command) || commandContains(command, ["keep", "default", "detour is ok", "detour is okay"]) || command == "detour" {
                liveSpeech.cancel()
                store.acceptDefaultAgentName()
                startPrompt()
            } else if let candidate = spokenAgentNameCandidate(value, allowBareName: false) {
                liveSpeech.cancel()
                store.agentNameDraft = candidate
                store.submitAgentName()
                startPrompt()
            } else if isNegative(command) || commandContains(command, ["rename", "change"]) {
                liveSpeech.cancel()
                store.startRenamingAgent()
                startPrompt()
            }
        case .renamingAgent:
            if isContinueCommand(command), !store.agentNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                liveSpeech.cancel()
                store.submitAgentName()
                startPrompt()
            } else {
                guard let candidate = spokenAgentNameCandidate(value, allowBareName: true),
                      !isContinueCommand(command) else { return }
                store.agentNameDraft = candidate
                inputField.stringValue = candidate
                liveSpeech.cancel()
                store.submitAgentName()
                startPrompt()
            }
        case .choosingVoice:
            if commandContains(command, ["preview", "hear", "play"]) {
                previewVoiceFromSpeech()
            } else if isAffirmative(command) || commandContains(command, ["select", "use", "continue"]) {
                liveSpeech.cancel()
                store.confirmVoice()
                startPrompt()
            }
        case .askingVoiceRecognition:
            if isNegative(command) {
                liveSpeech.cancel()
                store.skipVoiceEnrollment()
                startPrompt()
            } else if isAffirmative(command) || commandContains(command, ["set up", "learn", "voice"]) {
                liveSpeech.cancel()
                store.beginVoiceRecognitionSetup()
                voiceRecorder.reset()
                startPrompt()
            }
        case .settingWakeWord:
            if isContinueCommand(command), !store.wakeWordDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                liveSpeech.cancel()
                store.submitWakeWord()
                startPrompt()
            } else {
                let wakeWord = spokenValue(value, dropping: ["wake word is", "the wake word is", "listen for"])
                guard !wakeWord.isEmpty, !isContinueCommand(command) else { return }
                store.wakeWordDraft = wakeWord
                inputField.stringValue = wakeWord
                liveSpeech.cancel()
                store.submitWakeWord()
                startPrompt()
            }
        case .askingDeviceSetup:
            if isAffirmative(command) {
                liveSpeech.cancel()
                store.setWantsOtherAppleDevices(true)
                startPrompt()
            } else if isNegative(command) {
                liveSpeech.cancel()
                store.setWantsOtherAppleDevices(false)
                startPrompt()
            }
        case .choosingDevices:
            applyDeviceChoices(from: command)
            reloadDeviceChoices()
            if commandContains(command, ["finish", "done", "complete", "continue"])
                || canContinueDeviceSelectionFromSpeech {
                liveSpeech.cancel()
                store.continueToPairingQRCode()
                startPrompt()
            }
        case .showingPairingQRCode:
            if commandContains(command, ["done", "complete", "finish", "continue"]) {
                liveSpeech.cancel()
                store.finishCurrentDeviceSetup()
                startPrompt()
            }
        case .askingPersonalizationScan:
            if isAffirmative(command) || commandContains(command, ["scan", "learn", "personalize"]) {
                liveSpeech.cancel()
                store.askCredentialInheritanceForPersonalization()
                startPrompt()
            } else if isNegative(command) {
                liveSpeech.cancel()
                store.skipPersonalizationScan()
                startPrompt()
            }
        case .askingCredentialInheritance:
            if isAffirmative(command) || commandContains(command, ["allow", "inherit", "keys", "cookies", "auth"]) {
                liveSpeech.cancel()
                store.setCredentialInheritanceConsent(true)
                runPersonalizationScanFromUI()
            } else if isNegative(command) {
                liveSpeech.cancel()
                store.setCredentialInheritanceConsent(false)
                runPersonalizationScanFromUI()
            }
        case .runningPersonalizationScan:
            break
        case .reviewingPersonalizationScan:
            if applyPersonalizationSelectionCommand(command) {
                reloadPersonalizationViews()
                return
            }
            if isContinueCommand(command) || commandContains(command, ["done", "finish", "complete"]) {
                liveSpeech.cancel()
                if store.setupApplicationReport == nil {
                    applyPersonalizationSetupFromUI()
                    return
                }
                let advanced = store.continueFromPersonalizationReview()
                reloadPersonalizationViews()
                if advanced {
                    startPrompt()
                }
            }
        case .enrollingVoice:
            if isNegative(command) {
                liveSpeech.cancel()
                voiceRecorder.reset()
                store.skipVoiceEnrollment()
                startPrompt()
            } else if commandContains(command, ["record", "start", "sample", "enroll"]) {
                recordVoiceSampleFromSpeech()
            } else if isContinueCommand(command), voiceRecorder.hasSample {
                liveSpeech.cancel()
                store.completeVoiceEnrollment()
                startPrompt()
            }
        case .complete:
            break
        }
    }

}
