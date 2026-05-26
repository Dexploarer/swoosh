// DetourOnboardingContentViewSetup.swift — Detour onboarding view slice (0.5A)

import AppKit
import QuartzCore

extension DetourOnboardingContentView {
    func setup() {
        wantsLayer = true
        liveSpeech.onTranscript = { [weak self] transcript in
            self?.applyPartialVoiceInput(transcript)
        }
        liveSpeech.onFinalTranscript = { [weak self] transcript in
            self?.handleFinalVoiceInput(transcript)
        }

        blurView.material = .hudWindow
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        addSubview(blurView)

        promptField.font = .systemFont(ofSize: 58, weight: .semibold)
        promptField.textColor = .white
        promptField.alignment = .center
        promptField.maximumNumberOfLines = 0
        promptField.lineBreakMode = .byWordWrapping
        promptField.cell?.wraps = true
        promptField.cell?.isScrollable = false
        promptField.shadow = promptShadow
        addSubview(promptField)

        inputField.delegate = self
        inputField.font = .systemFont(ofSize: 40, weight: .medium)
        inputField.textColor = .white
        inputField.alignment = .center
        inputField.isBordered = false
        inputField.isBezeled = false
        inputField.drawsBackground = false
        inputField.focusRingType = .none
        inputField.maximumNumberOfLines = 1
        inputField.shadow = inputShadow
        addSubview(inputField)

        inputLine.wantsLayer = true
        inputLine.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.76).cgColor
        inputLine.shadow = inputShadow
        addSubview(inputLine)

        setupVoiceControls()
        setupAgentNameDecisionControls()
        setupVoiceRecognitionControls()
        setupDeviceDecisionControls()
        setupDeviceSelectionControls()
        setupPairingControls()
        setupPersonalizationControls()
        setupNavigationControls()
        hideInput()
        hideStepControls(animated: false)
        reloadNavigationControls()
        Task { [weak self] in
            guard let self else { return }
            _ = await liveSpeech.requestAuthorization()
        }
    }

    var promptShadow: NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.96)
        shadow.shadowBlurRadius = 30
        shadow.shadowOffset = NSSize(width: 0, height: -16)
        return shadow
    }

    var inputShadow: NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.82)
        shadow.shadowBlurRadius = 22
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        return shadow
    }

    func startPrompt() {
        streamTask?.cancel()
        renderedStep = store.step
        acceptsLiveSpeechInput = false
        liveSpeech.cancel()
        reloadNavigationControls()
        hideInput()
        hideStepControls(animated: false)
        promptField.stringValue = ""

        streamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if store.step == .askingDeviceSetup || store.step == .choosingDevices {
                await refreshDiscoveredDevices()
            }
            guard !Task.isCancelled else { return }
            let prompt = store.promptText
            currentPromptForSpeechFiltering = prompt
            let speechConfig = store.config.speech
            let promptSpeechTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await speech.speakAndWait(prompt, speech: speechConfig)
            }

            for character in prompt {
                if Task.isCancelled {
                    promptSpeechTask.cancel()
                    speech.stop()
                    return
                }
                promptField.stringValue.append(character)
                needsLayout = true
                try? await Task.sleep(for: .milliseconds(character == " " ? 12 : 24))
            }

            try? await Task.sleep(for: .milliseconds(180))
            showInputIfNeeded()
            showControlsForCurrentStep()
            resumePersonalizationScanIfNeeded()
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else {
                promptSpeechTask.cancel()
                speech.stop()
                liveSpeech.cancel()
                return
            }
            if store.step == .enrollingVoice {
                await promptSpeechTask.value
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                recordVoiceSampleFromSpeech()
                return
            }
            if store.step == .complete {
                await promptSpeechTask.value
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                exit()
                return
            }
            lastHandledFinalVoiceInput = ""
            acceptsLiveSpeechInput = true
            await beginLiveSpeechCapture(stopCurrentSpeech: false)
            await promptSpeechTask.value
        }
    }

    func refreshDiscoveredDevices() async {
        let devices = await deviceDiscovery.discover()
        guard !Task.isCancelled else { return }
        store.mergeDiscoveredDevices(devices)
    }

    func showInputIfNeeded() {
        switch store.step {
        case .askingName:
            showInput(placeholder: "Your name", value: store.userNameDraft)
        case .askingAgentName:
            hideInput()
        case .renamingAgent:
            showInput(placeholder: "Agent name", value: store.agentNameDraft)
            hideStepControls(animated: false)
        case .choosingVoice:
            hideInput()
            reloadVoiceChoices()
            hideStepControls(animated: false)
        case .askingVoiceRecognition, .enrollingVoice:
            hideInput()
            hideStepControls(animated: false)
        case .settingWakeWord:
            let draft = store.wakeWordDraft == store.defaultWakeWord ? "" : store.wakeWordDraft
            showInput(placeholder: store.defaultWakeWord, value: draft)
            hideStepControls(animated: false)
        case .askingDeviceSetup, .choosingDevices, .showingPairingQRCode, .askingPersonalizationScan,
             .askingCredentialInheritance, .runningPersonalizationScan, .reviewingPersonalizationScan:
            hideInput()
            hideStepControls(animated: false)
        case .complete:
            hideInput()
            hideStepControls(animated: true)
        }
    }

    func showInput(placeholder: String, value: String) {
        inputField.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.56),
                .font: NSFont.systemFont(ofSize: 32, weight: .medium)
            ]
        )
        inputField.stringValue = value
        inputField.maximumNumberOfLines = 1
        inputField.lineBreakMode = .byTruncatingTail
        inputField.cell?.wraps = false
        inputField.isHidden = false
        inputLine.isHidden = false
        window?.makeFirstResponder(inputField)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            window?.makeFirstResponder(inputField)
            (inputField.currentEditor() as? NSTextView)?.insertionPointColor = .white
        }
    }

    func hideInput() {
        inputField.isHidden = true
        inputLine.isHidden = true
    }

}
