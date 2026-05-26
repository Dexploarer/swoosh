// DetouriOSOnboardingView.swift — rebuilt iPhone onboarding surface (0.5A)

import SwiftUI
import UIKit

struct DetouriOSOnboardingView: View {
    @ObservedObject var store: DetouriOSOnboardingStore
    @ObservedObject var speech: DetouriOSSpeechService
    @StateObject private var recorder = DetouriOSVoiceEnrollmentRecorder()
    @StateObject private var liveSpeech = DetouriOSLiveSpeechRecognizer()
    @State private var renderedPrompt = ""
    @State private var controlsVisible = false
    @State private var lastHandledFinalVoiceInput = ""
    @State private var acceptsLiveSpeechInput = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                DetourFrostedBackground()

                VStack(spacing: 28) {
                    Spacer(minLength: 44)

                    Text(renderedPrompt)
                        .font(.system(size: promptFontSize(for: proxy), weight: .semibold))
                        .foregroundStyle(DetourPalette.offWhite)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .minimumScaleFactor(0.72)
                        .shadow(color: .black.opacity(0.95), radius: 26, x: 0, y: 16)
                        .frame(maxWidth: promptWidth(for: proxy), minHeight: 188)
                        .accessibilityIdentifier("detour.prompt")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(renderedPrompt.isEmpty ? store.promptText : renderedPrompt)
                        .accessibilitySortPriority(3)

                    controls
                        .frame(maxWidth: controlsWidth(for: proxy))
                        .accessibilitySortPriority(2)

                    statusStack
                        .frame(maxWidth: controlsWidth(for: proxy))
                        .accessibilitySortPriority(1)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 24)

                if store.canGoBack {
                    VStack {
                        HStack {
                            backButton
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(.top, proxy.safeAreaInsets.top + 12)
                    .padding(.leading, 18)
                    .padding(.trailing, 18)
                }
            }
        }
        .task(id: store.promptRequestIdentity) {
            let prompt = store.resolvePromptText()
            if !Task.isCancelled {
                await streamPrompt(prompt)
            }
        }
        .task {
            _ = await liveSpeech.requestAuthorization()
        }
        .task {
            speech.prepareLocalVoice()
        }
        .task(id: store.pairedMac?.host) {
            if store.pairedMac != nil {
                await store.reconnectPairedMac()
            }
        }
        .onChange(of: liveSpeech.transcript) { _, transcript in
            applyPartialVoiceInput(transcript)
        }
        .onChange(of: liveSpeech.finalTranscript) { _, transcript in
            handleFinalVoiceInput(transcript)
        }
        .userActivity(DetouriOSUserActivity.onboardingType, isActive: store.step != .complete) { activity in
            let current = DetouriOSUserActivity.makeOnboardingActivity(step: store.step)
            activity.title = current.title
            activity.isEligibleForSearch = current.isEligibleForSearch
            activity.isEligibleForPrediction = current.isEligibleForPrediction
            activity.persistentIdentifier = current.persistentIdentifier
            activity.targetContentIdentifier = current.targetContentIdentifier
            activity.userInfo = current.userInfo
            activity.requiredUserInfoKeys = current.requiredUserInfoKeys
            activity.needsSave = true
        }
    }

    @ViewBuilder
    private var controls: some View {
        if controlsVisible {
            switch store.step {
            case .askingName:
                bareInput(
                    placeholder: "Your name",
                    text: $store.userNameDraft,
                    submitLabel: .continue,
                    submit: store.submitName
                )
            case .askingAgentName:
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        DetourGlassButton(title: "Keep Detour", systemName: "checkmark", isProminent: true) {
                            store.acceptDefaultAgentName()
                        }
                        DetourGlassButton(title: "Rename", systemName: "pencil", isProminent: false) {
                            store.startRenamingAgent()
                        }
                    }
                    bareInput(
                        placeholder: "Or type a new name",
                        text: $store.agentNameDraft,
                        submitLabel: .done,
                        submit: store.submitAgentName
                    )
                }
            case .renamingAgent:
                bareInput(
                    placeholder: "Agent name",
                    text: $store.agentNameDraft,
                    submitLabel: .done,
                    submit: store.submitAgentName
                )
            case .choosingVoice:
                if store.hasRealVoiceChoice {
                    voicePicker
                }
            case .settingWakeWord:
                bareInput(
                    placeholder: store.defaultWakeWord,
                    text: $store.wakeWordDraft,
                    submitLabel: .continue,
                    submit: store.submitWakeWord
                )
            case .askingVoiceRecognition:
                HStack(spacing: 12) {
                    DetourGlassButton(title: "Set up voice", systemName: "waveform", isProminent: true) {
                        liveSpeech.cancel()
                        store.beginVoiceRecognitionSetup()
                    }
                    DetourGlassButton(title: "Later", systemName: "clock", isProminent: false) {
                        liveSpeech.cancel()
                        store.skipVoiceEnrollment()
                    }
                }
            case .enrollingVoice:
                voiceEnrollmentControls
            case .askingDeviceSetup:
                HStack(spacing: 12) {
                    DetourGlassButton(title: "Yes", systemName: "link", isProminent: true) {
                        store.setWantsOtherAppleDevices(true)
                    }
                    DetourGlassButton(title: "Not now", systemName: "xmark", isProminent: false) {
                        store.setWantsOtherAppleDevices(false)
                    }
                }
            case .choosingDevices:
                deviceSelectionControls
            case .reviewingInheritedSetup:
                inheritedSetupControls
            case .complete:
                completionControls
            }
        }
    }

    private var voicePicker: some View {
        VStack(spacing: 14) {
            DetourLocalVoiceControl(
                title: speech.localVoiceTitle,
                isSelected: true
            ) {
                speech.selectLocalVoice()
            }
            .task {
                speech.selectLocalVoice()
            }

            HStack(spacing: 12) {
                DetourGlassButton(title: "Preview", systemName: "speaker.wave.2", isProminent: false) {
                    speech.selectLocalVoice()
                    speech.speak(store.voicePreviewText, speech: store.config.speech)
                }
                DetourGlassButton(title: "Select", systemName: "checkmark", isProminent: true) {
                    speech.selectLocalVoice()
                    store.confirmVoice()
                }
            }
        }
    }

    private var backButton: some View {
        Button {
            goBackFromUI()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(DetourPalette.offWhite)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .background(DetourPalette.graphite.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DetourPalette.silver.opacity(0.24), lineWidth: 1))
        .shadow(color: .black.opacity(0.24), radius: 14, x: 0, y: 8)
        .accessibilityIdentifier("detour.back")
        .accessibilityLabel("Back")
    }

    private var voiceEnrollmentControls: some View {
        VStack(spacing: 16) {
            Text(recorder.statusText)
                .font(.callout.weight(.medium))
                .foregroundStyle(.white.opacity(0.82))

            HStack(spacing: 12) {
                DetourGlassButton(
                    title: recorder.isRecording ? "Stop" : "Record",
                    systemName: recorder.isRecording ? "stop.fill" : "mic.fill",
                    isProminent: true
                ) {
                    Task {
                        do {
                            liveSpeech.cancel()
                            speech.stop()
                            let sampleURL = try store.voiceEnrollmentSampleURL()
                            await recorder.toggleRecording(sampleURL: sampleURL)
                        } catch {
                            recorder.fail(error.localizedDescription)
                        }
                    }
                }

                DetourGlassButton(title: "Skip", systemName: "clock", isProminent: false) {
                    liveSpeech.cancel()
                    recorder.stopRecording()
                    store.skipVoiceEnrollment()
                }

                DetourGlassButton(title: "Continue", systemName: "arrow.right", isProminent: recorder.hasRecording) {
                    liveSpeech.cancel()
                    recorder.stopRecording()
                    store.completeVoiceEnrollment()
                }
                .disabled(!recorder.hasRecording)
                .opacity(recorder.hasRecording ? 1 : 0.52)
            }
        }
    }

    private var deviceSelectionControls: some View {
        VStack(spacing: 18) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
                ForEach(store.availableDeviceKinds) { device in
                    DetourDeviceChoiceButton(
                        device: device,
                        isSelected: store.selectedDeviceKinds.contains(device)
                    ) {
                        store.toggleDevice(device)
                    }
                }
            }

            if store.selectedDeviceKinds.contains(.remoteDetour) {
                VStack(spacing: 12) {
                    bareInput(
                        placeholder: "Remote host",
                        text: $store.remoteHostDraft,
                        submitLabel: .next,
                        submit: {}
                    )
                    bareInput(
                        placeholder: "SSH user",
                        text: $store.remoteUserDraft,
                        submitLabel: .next,
                        submit: {}
                    )
                    bareInput(
                        placeholder: "SSH port",
                        text: $store.remotePortDraft,
                        submitLabel: .done,
                        submit: {}
                    )
                    .keyboardType(.numberPad)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            DetourGlassButton(title: "Finish", systemName: "checkmark", isProminent: true) {
                store.completeDeviceSetup()
            }
        }
    }

    private var completionControls: some View {
        VStack(spacing: 14) {
            if store.pairedMac != nil {
                DetourGlassButton(title: "Check Mac", systemName: "antenna.radiowaves.left.and.right", isProminent: false) {
                    Task {
                        await store.reconnectPairedMac()
                    }
                }
            }
        }
    }

    private var inheritedSetupControls: some View {
        VStack(spacing: 14) {
            if let pairingStatus = store.pairingStatusText {
                DetourStatusPill(text: pairingStatus, systemName: "macbook.and.iphone")
            }
            DetourGlassButton(title: "Use this setup", systemName: "checkmark", isProminent: true) {
                store.finishInheritedSetupReview()
            }
        }
    }

    @ViewBuilder
    private var statusStack: some View {
        VStack(spacing: 10) {
            if let pairingStatus = store.pairingStatusText {
                DetourStatusPill(text: pairingStatus, systemName: "link")
            }
            if let pairingError = store.pairingError {
                DetourStatusPill(text: pairingError, systemName: "exclamationmark.triangle")
            }
            if let storageError = store.storageError {
                DetourStatusPill(text: storageError, systemName: "externaldrive.badge.exclamationmark")
            }
            if let speechError = liveSpeech.lastErrorText {
                DetourStatusPill(text: speechError, systemName: "mic.slash")
            }
            if controlsVisible && stepAllowsLiveSpeech {
                DetourVoiceInputButton(isListening: liveSpeech.isListening) {
                    Task {
                        await toggleLiveSpeechCapture()
                    }
                }
            }
        }
    }

    private func bareInput(
        placeholder: String,
        text: Binding<String>,
        submitLabel: SubmitLabel,
        submit: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            TextField("", text: text, prompt: Text(placeholder).foregroundStyle(DetourPalette.silver.opacity(0.68)))
                .focused($inputFocused)
                .textFieldStyle(.plain)
                .font(.system(size: 31, weight: .medium))
                .foregroundStyle(DetourPalette.offWhite)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(submitLabel)
                .onSubmit(submit)
                .shadow(color: .black.opacity(0.8), radius: 18, x: 0, y: 10)
                .frame(minHeight: 58)
                .contentShape(Rectangle())
                .accessibilityLabel(placeholder)

            Rectangle()
                .fill(DetourPalette.rust.opacity(0.84))
                .frame(height: 2)
                .shadow(color: .black.opacity(0.7), radius: 10, x: 0, y: 8)
        }
        .padding(.horizontal, 4)
    }

    @MainActor
    private func streamPrompt(_ prompt: String) async {
        controlsVisible = false
        inputFocused = false
        acceptsLiveSpeechInput = false
        liveSpeech.cancel()
        renderedPrompt = ""
        let promptSpeechTask: Task<Void, Never>? = UIAccessibility.isVoiceOverRunning
            ? nil
            : Task { await speech.speakAndWait(prompt, speech: store.config.speech) }

        for character in prompt {
            if Task.isCancelled {
                promptSpeechTask?.cancel()
                speech.stop()
                return
            }

            renderedPrompt.append(character)
            try? await Task.sleep(for: .milliseconds(character == " " ? 12 : 24))
        }

        try? await Task.sleep(for: .milliseconds(180))
        withAnimation(.smooth(duration: 0.42)) {
            controlsVisible = true
        }
        try? await Task.sleep(for: .milliseconds(120))
        if !Task.isCancelled {
            inputFocused = stepNeedsInput
            await beginLiveSpeechCapture(stopCurrentSpeech: false)
            await promptSpeechTask?.value
            lastHandledFinalVoiceInput = ""
            acceptsLiveSpeechInput = true
        } else {
            promptSpeechTask?.cancel()
            speech.stop()
            liveSpeech.cancel()
        }
    }

    @MainActor
    private func beginLiveSpeechCapture(stopCurrentSpeech: Bool) async {
        guard stepAllowsLiveSpeech, !liveSpeech.isListening else { return }
        guard await liveSpeech.requestAuthorization() == .authorized else { return }
        if stopCurrentSpeech {
            speech.stop()
        }
        lastHandledFinalVoiceInput = ""
        try? await liveSpeech.start()
    }

    @MainActor
    private func toggleLiveSpeechCapture() async {
        if liveSpeech.isListening {
            liveSpeech.stop()
            acceptsLiveSpeechInput = false
        } else {
            acceptsLiveSpeechInput = true
            await beginLiveSpeechCapture(stopCurrentSpeech: true)
        }
    }

    private var stepAllowsLiveSpeech: Bool {
        switch store.step {
        case .askingAgentName, .enrollingVoice, .reviewingInheritedSetup, .complete:
            false
        case .askingName, .renamingAgent, .choosingVoice, .settingWakeWord,
             .askingVoiceRecognition, .askingDeviceSetup, .choosingDevices:
            true
        }
    }

    private func applyPartialVoiceInput(_ transcript: String) {
        guard liveSpeech.isListening else { return }
        guard acceptsLiveSpeechInput else { return }
        let value = cleanedSpokenValue(transcript)
        guard !value.isEmpty else { return }

        switch store.step {
        case .askingName:
            store.userNameDraft = cleanName(spokenValue(value, dropping: ["my name is", "my name's", "i'm", "i am", "this is", "it is", "it's", "its"]))
        case .askingAgentName:
            break
        case .renamingAgent:
            if let candidate = spokenAgentNameCandidate(value, allowBareName: true) {
                store.agentNameDraft = candidate
            }
        case .settingWakeWord:
            store.wakeWordDraft = spokenValue(value, dropping: ["wake word is", "the wake word is", "listen for"])
        case .choosingDevices:
            applyRemoteDrafts(from: value)
        case .choosingVoice, .askingVoiceRecognition, .enrollingVoice, .askingDeviceSetup, .reviewingInheritedSetup, .complete:
            break
        }
    }

    private func handleFinalVoiceInput(_ transcript: String) {
        guard acceptsLiveSpeechInput else { return }
        let value = cleanedSpokenValue(transcript)
        guard !value.isEmpty else { return }
        guard consumeFinalVoiceInput(value) else { return }
        let command = value.lowercased()
        if isBackCommand(command), store.canGoBack {
            goBackFromUI()
            return
        }

        switch store.step {
        case .askingName:
            liveSpeech.cancel()
            store.userNameDraft = cleanName(spokenValue(value, dropping: ["my name is", "my name's", "i'm", "i am", "this is", "it is", "it's", "its"]))
            store.submitName()
        case .askingAgentName:
            if isAffirmative(command) || commandContains(command, ["keep", "default", "detour is ok", "detour is okay"]) || command == "detour" {
                liveSpeech.cancel()
                store.acceptDefaultAgentName()
            } else if let candidate = spokenAgentNameCandidate(value, allowBareName: false) {
                liveSpeech.cancel()
                store.agentNameDraft = candidate
                store.submitAgentName()
            } else if commandContains(command, ["rename", "change"]) {
                liveSpeech.cancel()
                store.startRenamingAgent()
            }
        case .renamingAgent:
            guard let candidate = spokenAgentNameCandidate(value, allowBareName: true) else { return }
            liveSpeech.cancel()
            store.agentNameDraft = candidate
            store.submitAgentName()
        case .choosingVoice:
            if commandContains(command, ["preview", "hear", "play"]) {
                speech.selectLocalVoice()
                speech.speak(store.voicePreviewText, speech: store.config.speech)
            } else if isAffirmative(command) || commandContains(command, ["select", "use", "continue"]) {
                liveSpeech.cancel()
                speech.selectLocalVoice()
                store.confirmVoice()
            }
        case .settingWakeWord:
            liveSpeech.cancel()
            store.wakeWordDraft = spokenValue(value, dropping: ["wake word is", "the wake word is", "listen for"])
            store.submitWakeWord()
        case .askingVoiceRecognition:
            if isNegative(command) {
                liveSpeech.cancel()
                store.skipVoiceEnrollment()
            } else if isAffirmative(command) || commandContains(command, ["set up", "learn", "voice"]) {
                liveSpeech.cancel()
                store.beginVoiceRecognitionSetup()
            }
        case .enrollingVoice:
            break
        case .askingDeviceSetup:
            if isAffirmative(command) {
                liveSpeech.cancel()
                store.setWantsOtherAppleDevices(true)
            } else if isNegative(command) {
                liveSpeech.cancel()
                store.setWantsOtherAppleDevices(false)
            }
        case .choosingDevices:
            applyDeviceChoices(from: command)
            if commandContains(command, ["finish", "done", "complete", "continue"]) {
                liveSpeech.cancel()
                store.completeDeviceSetup()
            }
        case .reviewingInheritedSetup:
            if isAffirmative(command) || commandContains(command, ["continue", "use", "finish", "done"]) {
                liveSpeech.cancel()
                store.finishInheritedSetupReview()
            }
        case .complete:
            break
        }
    }

    private func goBackFromUI() {
        liveSpeech.cancel()
        recorder.stopRecording()
        speech.stop()
        store.goBack()
    }

    private func consumeFinalVoiceInput(_ value: String) -> Bool {
        let fingerprint = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard fingerprint != lastHandledFinalVoiceInput else { return false }
        lastHandledFinalVoiceInput = fingerprint
        return true
    }

    private func applyRemoteDrafts(from value: String) {
        let command = value.lowercased()
        guard store.selectedDeviceKinds.contains(.remoteDetour) else { return }
        if command.contains(".") || command.contains(":") {
            store.remoteHostDraft = value
        }
    }

    private func applyDeviceChoices(from command: String) {
        for device in store.availableDeviceKinds where commandMentions(device, in: command) {
            if !store.selectedDeviceKinds.contains(device) {
                store.toggleDevice(device)
            }
        }
    }

    private func commandMentions(_ device: DetouriOSDeviceKind, in command: String) -> Bool {
        switch device {
        case .macBook:
            return command.contains("macbook") || command.contains("mac book") || command.contains("laptop")
        case .macMini:
            return command.contains("mac mini") || command.contains("mini")
        case .iPhone:
            return command.contains("iphone") || command.contains("phone")
        case .iPad:
            return command.contains("ipad") || command.contains("tablet")
        case .appleWatch:
            return command.contains("apple watch") || command.contains("watch")
        case .iMac:
            return command.contains("imac")
        case .macStudio:
            return command.contains("mac studio") || command.contains("studio")
        case .visionPro:
            return command.contains("vision") || command.contains("vision pro")
        case .remoteDetour:
            return command.contains("remote") || command.contains("server")
        }
    }

    private func cleanedSpokenValue(_ transcript: String) -> String {
        transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:"))
    }

    private func spokenValue(_ value: String, dropping prefixes: [String]) -> String {
        let normalizedValue = removingLeadingFillers(from: value)
        let lowercased = normalizedValue.lowercased()
        for prefix in prefixes where lowercased.hasPrefix(prefix) {
            return String(normalizedValue.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:"))
        }
        return normalizedValue
    }

    private func cleanName(_ value: String) -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased() == "detour" {
            return ""
        }
        return name
    }

    private func spokenAgentNameCandidate(_ value: String, allowBareName: Bool) -> String? {
        let normalizedValue = removingLeadingFillers(from: value)
        let explicitPrefixes = [
            "call you",
            "call yourself",
            "name you",
            "name it",
            "your name is",
            "you are",
            "you're",
            "rename you to",
            "change your name to",
            "let's call you",
            "lets call you",
            "i'll call you",
            "ill call you"
        ]
        let lowercased = normalizedValue.lowercased()
        let explicitCandidate = explicitPrefixes.compactMap { prefix -> String? in
            guard lowercased.hasPrefix(prefix) else { return nil }
            return String(normalizedValue.dropFirst(prefix.count))
        }.first
        guard let candidate = explicitCandidate ?? (allowBareName ? normalizedValue : nil) else {
            return nil
        }
        return cleanedAgentNameCandidate(candidate)
    }

    private func cleanedAgentNameCandidate(_ value: String) -> String? {
        let candidate = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:"))
        guard !candidate.isEmpty else { return nil }
        let lowercased = candidate.lowercased()
        let selfIntroTerms = ["my name", "i'm", "i am", "im ", "it's me", "its me", "this is"]
        guard !commandContains(lowercased, selfIntroTerms) else { return nil }
        guard !namesMatch(candidate, store.userName) else { return nil }
        guard !containsName(candidate, store.userName) else { return nil }
        return candidate
    }

    private func removingLeadingFillers(from value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let fillers = ["hey ", "hi ", "hello ", "yo "]
        while let filler = fillers.first(where: { result.lowercased().hasPrefix($0) }) {
            result = String(result.dropFirst(filler.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        == rhs.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func containsName(_ value: String, _ name: String) -> Bool {
        let canonicalValue = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let canonicalName = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !canonicalName.isEmpty else { return false }
        return canonicalValue
            .split { !$0.isLetter && !$0.isNumber }
            .contains { String($0) == canonicalName }
    }

    private func commandContains(_ command: String, _ terms: [String]) -> Bool {
        terms.contains { command.contains($0) }
    }

    private func isAffirmative(_ command: String) -> Bool {
        commandContains(command, ["yes", "yeah", "yep", "sure", "ok", "okay", "please", "do it"])
    }

    private func isNegative(_ command: String) -> Bool {
        commandContains(command, ["no", "nope", "later", "not now", "skip"])
    }

    private func isBackCommand(_ command: String) -> Bool {
        command == "back"
            || command == "go back"
            || command == "previous"
            || command == "go previous"
            || command == "change that"
            || command == "redo that"
    }

    private var stepNeedsInput: Bool {
        switch store.step {
        case .askingName, .askingAgentName, .renamingAgent, .settingWakeWord:
            true
        case .choosingVoice, .askingVoiceRecognition, .enrollingVoice,
             .askingDeviceSetup, .choosingDevices, .reviewingInheritedSetup, .complete:
            false
        }
    }

    private func promptFontSize(for proxy: GeometryProxy) -> CGFloat {
        proxy.size.width < 390 ? 34 : 38
    }

    private func promptWidth(for proxy: GeometryProxy) -> CGFloat {
        min(proxy.size.width - 36, 620)
    }

    private func controlsWidth(for proxy: GeometryProxy) -> CGFloat {
        min(proxy.size.width - 40, 620)
    }
}

private enum DetourPalette {
    static let graphite = Color(red: 0.035, green: 0.035, blue: 0.04)
    static let carbon = Color(red: 0.08, green: 0.075, blue: 0.07)
    static let silver = Color(red: 0.72, green: 0.73, blue: 0.75)
    static let offWhite = Color(red: 0.96, green: 0.95, blue: 0.92)
    static let rust = Color(red: 0.78, green: 0.29, blue: 0.12)
    static let deepRust = Color(red: 0.46, green: 0.13, blue: 0.055)
}

private struct DetourVoiceInputButton: View {
    let isListening: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isListening ? "waveform.circle.fill" : "mic.circle.fill")
                .font(.system(size: 34, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isListening ? DetourPalette.rust : DetourPalette.offWhite)
                .frame(width: 58, height: 58)
        }
        .buttonStyle(.plain)
        .background(DetourPalette.graphite.opacity(0.72), in: Circle())
        .overlay(Circle().stroke((isListening ? DetourPalette.rust : DetourPalette.silver).opacity(0.58), lineWidth: 1))
        .shadow(color: .black.opacity(0.24), radius: 14, x: 0, y: 8)
        .accessibilityIdentifier("detour.voiceInput")
        .accessibilityLabel(isListening ? "Stop voice input" : "Start voice input")
    }
}

private struct DetourFrostedBackground: View {
    var body: some View {
        ZStack {
            Rectangle().fill(DetourPalette.graphite)
            LinearGradient(
                colors: [
                    .black,
                    DetourPalette.carbon,
                    DetourPalette.deepRust.opacity(0.58),
                    .black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LinearGradient(
                colors: [
                    DetourPalette.silver.opacity(0.14),
                    .clear,
                    DetourPalette.rust.opacity(0.18)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

private struct DetourGlassButton: View {
    let title: String
    let systemName: String
    let isProminent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isProminent ? DetourPalette.offWhite : DetourPalette.silver)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.horizontal, 10)
        }
        .buttonStyle(.plain)
        .background(buttonFill, in: Capsule())
        .overlay(Capsule().stroke((isProminent ? DetourPalette.rust : DetourPalette.silver).opacity(isProminent ? 0.62 : 0.28), lineWidth: 1))
        .shadow(color: .black.opacity(isProminent ? 0.34 : 0.22), radius: 16, x: 0, y: 10)
        .accessibilityIdentifier("detour.button.\(title)")
        .accessibilityLabel(title)
    }

    private var buttonFill: AnyShapeStyle {
        isProminent
            ? AnyShapeStyle(
                LinearGradient(
                    colors: [DetourPalette.rust.opacity(0.92), DetourPalette.deepRust.opacity(0.9)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            : AnyShapeStyle(DetourPalette.graphite.opacity(0.66))
    }
}

private struct DetourLocalVoiceControl: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.badge.sparkle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DetourPalette.rust)

                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .foregroundStyle(DetourPalette.offWhite)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .padding(.horizontal, 18)
        }
        .buttonStyle(.plain)
        .background(isSelected ? DetourPalette.deepRust.opacity(0.82) : DetourPalette.graphite.opacity(0.66), in: Capsule())
        .overlay(Capsule().stroke((isSelected ? DetourPalette.rust : DetourPalette.silver).opacity(isSelected ? 0.66 : 0.24), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 10)
        .accessibilityLabel(title)
    }
}

private struct DetourVoiceChoiceButton: View {
    let voice: DetouriOSVoice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(voice.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(voice.qualityLabel)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(DetourPalette.silver.opacity(0.78))
            }
            .foregroundStyle(DetourPalette.offWhite)
            .frame(width: 112, height: 58)
        }
        .buttonStyle(.plain)
        .background(isSelected ? DetourPalette.deepRust.opacity(0.82) : DetourPalette.graphite.opacity(0.66), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke((isSelected ? DetourPalette.rust : DetourPalette.silver).opacity(isSelected ? 0.66 : 0.22), lineWidth: 1)
        )
        .accessibilityLabel(voice.menuTitle(isRecommended: isSelected))
    }
}

private struct DetourDeviceChoiceButton: View {
    let device: DetouriOSDeviceKind
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: device.symbolName)
                    .font(.system(size: 27, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 42, height: 32)
                    .foregroundStyle(isSelected ? DetourPalette.rust : DetourPalette.silver)

                Text(device.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(DetourPalette.offWhite)
            }
            .frame(maxWidth: .infinity, minHeight: 86)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .background(deviceFill, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke((isSelected ? DetourPalette.rust : DetourPalette.silver).opacity(isSelected ? 0.62 : 0.24), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(device.displayName)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private var deviceFill: AnyShapeStyle {
        isSelected ? AnyShapeStyle(DetourPalette.deepRust.opacity(0.74)) : AnyShapeStyle(DetourPalette.graphite.opacity(0.64))
    }
}

private struct DetourStatusPill: View {
    let text: String
    let systemName: String

    var body: some View {
        Label(text, systemImage: systemName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(DetourPalette.silver)
            .lineLimit(3)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(DetourPalette.graphite.opacity(0.7), in: Capsule())
            .overlay(Capsule().stroke(DetourPalette.silver.opacity(0.2), lineWidth: 1))
    }
}
