// DetourOnboardingContentViewVoiceActions.swift — Detour onboarding view slice (0.5A)

import AppKit
import QuartzCore

extension DetourOnboardingContentView {
    func goBackFromUI() {
        guard store.canGoBack else { return }
        streamTask?.cancel()
        voiceRecordingTask?.cancel()
        if voiceRecorder.isRecording {
            voiceRecorder.stopRecording()
        }
        acceptsLiveSpeechInput = false
        liveSpeech.cancel()
        speech.stop()
        store.goBack()
        reloadNavigationControls()
        startPrompt()
    }

    func recordVoiceSampleFromSpeech() {
        acceptsLiveSpeechInput = false
        liveSpeech.cancel()
        speech.stop()
        voiceRecordingTask?.cancel()
        voiceRecordingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let sampleURL = try store.voiceEnrollmentSampleURL()
                await voiceRecorder.startRecording(to: sampleURL)
                reloadVoiceEnrollmentControls()
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                voiceRecorder.stopRecording()
                reloadVoiceEnrollmentControls()
                if voiceRecorder.hasSample {
                    store.completeVoiceEnrollment()
                    startPrompt()
                } else {
                    await beginLiveSpeechCapture(stopCurrentSpeech: false)
                    acceptsLiveSpeechInput = true
                }
            } catch {
                voiceRecorder.reset()
                reloadVoiceEnrollmentControls()
                await beginLiveSpeechCapture(stopCurrentSpeech: false)
                acceptsLiveSpeechInput = true
            }
        }
    }

    func previewVoiceFromSpeech() {
        acceptsLiveSpeechInput = false
        liveSpeech.cancel()
        let previewText = store.voicePreviewText
        let speechConfig = store.config.speech
        Task { @MainActor [weak self] in
            guard let self else { return }
            await speech.speakAndWait(previewText, speech: speechConfig)
            await beginLiveSpeechCapture(stopCurrentSpeech: false)
            acceptsLiveSpeechInput = true
        }
    }

    func runPersonalizationScanFromUI() {
        guard !personalizationScanTaskActive else { return }
        personalizationScanTaskActive = true
        acceptsLiveSpeechInput = false
        liveSpeech.cancel()
        speech.stop()
        store.startPersonalizationScan()
        startPrompt()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await store.runPersonalizationScan { [weak self] _ in
                self?.reloadPersonalizationViews()
            }
            personalizationScanTaskActive = false
            reloadPersonalizationViews()
            startPrompt()
        }
    }

    func resumePersonalizationScanIfNeeded() {
        guard store.step == .runningPersonalizationScan,
              store.personalizationResult == nil,
              !personalizationScanTaskActive else {
            return
        }
        personalizationScanTaskActive = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            await store.runPersonalizationScan { [weak self] _ in
                self?.reloadPersonalizationViews()
            }
            personalizationScanTaskActive = false
            reloadPersonalizationViews()
            startPrompt()
        }
    }

    func consumeFinalVoiceInput(_ value: String) -> Bool {
        let fingerprint = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard fingerprint != lastHandledFinalVoiceInput else { return false }
        lastHandledFinalVoiceInput = fingerprint
        return true
    }

    func isCurrentPromptEcho(_ value: String) -> Bool {
        let spokenWords = canonicalSpeechWords(value)
        guard spokenWords.count >= 4 else { return false }
        let promptWords = canonicalSpeechWords(currentPromptForSpeechFiltering)
        guard !promptWords.isEmpty else { return false }
        let prompt = promptWords.joined(separator: " ")
        let spoken = spokenWords.joined(separator: " ")
        if prompt.contains(spoken) || spoken.contains(prompt) {
            return true
        }
        let promptSet = Set(promptWords)
        let overlap = spokenWords.filter { promptSet.contains($0) }.count
        return Double(overlap) / Double(spokenWords.count) >= 0.72
    }

    func canonicalSpeechWords(_ value: String) -> [String] {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    func applyRemoteDrafts(from value: String) {
        let command = value.lowercased()
        guard store.selectedDeviceKinds.contains(.remoteDetour) else { return }
        if command.contains(".") || command.contains(":") {
            store.remoteHostDraft = value
            remoteHostField.stringValue = value
        }
    }

    var canContinueDeviceSelectionFromSpeech: Bool {
        guard !store.selectedDeviceKinds.isEmpty else { return false }
        if store.selectedDeviceKinds.contains(.remoteDetour) {
            return !store.remoteHostDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    func applyDeviceChoices(from command: String) {
        for device in store.availableDeviceKinds where commandMentions(device, in: command) {
            if !store.selectedDeviceKinds.contains(device) {
                store.toggleDevice(device)
            }
        }
    }

}
