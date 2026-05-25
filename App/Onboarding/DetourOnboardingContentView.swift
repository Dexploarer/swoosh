// DetourOnboardingContentView.swift — native frosted Detour onboarding input (0.5A)

import AppKit
import QuartzCore

@MainActor
final class DetourOnboardingContentView: NSView, NSTextFieldDelegate {
    private let store: OnboardingStore
    private let speech: DetourSpeechService
    private let exit: () -> Void
    private let blurView = NSVisualEffectView()
    private let promptField = NSTextField(labelWithString: "")
    private let inputField = DetourInputField()
    private let inputLine = NSView()
    private let voiceControlsView = NSView()
    private let voicePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let previewVoiceButton = NSButton(title: "Preview", target: nil, action: nil)
    private let selectVoiceButton = NSButton(title: "Select", target: nil, action: nil)
    private let agentNameDecisionView = NSView()
    private let keepAgentNameButton = NSButton(title: "Keep Detour", target: nil, action: nil)
    private let renameAgentButton = NSButton(title: "Rename", target: nil, action: nil)
    private let voiceRecognitionDecisionView = NSView()
    private let setupVoiceRecognitionButton = NSButton(title: "Set up voice", target: nil, action: nil)
    private let skipVoiceRecognitionButton = NSButton(title: "Later", target: nil, action: nil)
    private let voiceEnrollmentView = NSView()
    private let voiceEnrollmentStatusField = NSTextField(labelWithString: "")
    private let recordVoiceButton = NSButton(title: "Record", target: nil, action: nil)
    private let skipVoiceEnrollmentButton = NSButton(title: "Skip", target: nil, action: nil)
    private let continueVoiceEnrollmentButton = NSButton(title: "Continue", target: nil, action: nil)
    private let deviceDecisionView = NSView()
    private let yesDevicesButton = NSButton(title: "Yes", target: nil, action: nil)
    private let noDevicesButton = NSButton(title: "Not now", target: nil, action: nil)
    private let deviceSelectionView = NSView()
    private var deviceButtons: [DetourDeviceKind: DetourDeviceOptionButton] = [:]
    private let remoteHostField = DetourInputField()
    private let remoteUserField = DetourInputField()
    private let remotePortField = DetourInputField()
    private let continueDevicesButton = NSButton(title: "Continue", target: nil, action: nil)
    private let pairingView = NSView()
    private let qrImageView = NSImageView()
    private let pairingDetailField = NSTextField(labelWithString: "")
    private let donePairingButton = NSButton(title: "Done", target: nil, action: nil)
    private let voiceRecorder = DetourVoiceEnrollmentRecorder()
    private let liveSpeech = DetourLiveSpeechRecognizer()
    private let deviceDiscovery = DetourDeviceDiscovery()
    private var streamTask: Task<Void, Never>?
    private var voiceRecordingTask: Task<Void, Never>?
    private var agentNameDecisionVisible = false
    private var voiceControlsVisible = false
    private var voiceRecognitionDecisionVisible = false
    private var voiceEnrollmentVisible = false
    private var deviceDecisionVisible = false
    private var deviceSelectionVisible = false
    private var pairingVisible = false
    private var lastHandledFinalVoiceInput = ""
    private var acceptsLiveSpeechInput = false
    private var currentPromptForSpeechFiltering = ""

    init(frame frameRect: NSRect, store: OnboardingStore, speech: DetourSpeechService, exit: @escaping () -> Void) {
        self.store = store
        self.speech = speech
        self.exit = exit
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        streamTask?.cancel()
        voiceRecordingTask?.cancel()
    }

    override var acceptsFirstResponder: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        exit()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            exit()
            return
        }

        super.keyDown(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        startPrompt()
    }

    override func layout() {
        super.layout()
        blurView.frame = bounds

        let contentWidth = min(bounds.width - 152, 1220)
        let promptHeight = promptHeight(for: contentWidth)
        let inputWidth = min(bounds.width - 152, 680)
        let inputHeight: CGFloat = 68
        let promptY = (bounds.height - promptHeight) / 2 + 46

        promptField.frame = NSRect(
            x: (bounds.width - contentWidth) / 2,
            y: promptY,
            width: contentWidth,
            height: promptHeight
        )

        inputField.frame = NSRect(
            x: (bounds.width - inputWidth) / 2,
            y: promptY - inputHeight - 32,
            width: inputWidth,
            height: inputHeight
        )

        inputLine.frame = NSRect(
            x: inputField.frame.minX,
            y: inputField.frame.minY + 2,
            width: inputWidth,
            height: 2
        )

        let voiceWidth = min(bounds.width - 152, 760)
        let voiceHeight: CGFloat = 70
        voiceControlsView.frame = NSRect(
            x: (bounds.width - voiceWidth) / 2,
            y: promptY - voiceHeight - 42,
            width: voiceWidth,
            height: voiceHeight
        )

        let buttonWidth: CGFloat = 112
        let controlSpacing: CGFloat = 12
        let popupWidth = max(240, voiceWidth - (buttonWidth * 2) - (controlSpacing * 2))
        voicePopup.frame = NSRect(x: 0, y: 8, width: popupWidth, height: 52)
        previewVoiceButton.frame = NSRect(
            x: voicePopup.frame.maxX + controlSpacing,
            y: 8,
            width: buttonWidth,
            height: 52
        )
        selectVoiceButton.frame = NSRect(
            x: previewVoiceButton.frame.maxX + controlSpacing,
            y: 8,
            width: buttonWidth,
            height: 52
        )

        let agentNameDecisionWidth: CGFloat = 344
        let agentNameDecisionHeight: CGFloat = 70
        agentNameDecisionView.frame = NSRect(
            x: (bounds.width - agentNameDecisionWidth) / 2,
            y: promptY - agentNameDecisionHeight - 42,
            width: agentNameDecisionWidth,
            height: agentNameDecisionHeight
        )
        keepAgentNameButton.frame = NSRect(x: 0, y: 8, width: 168, height: 52)
        renameAgentButton.frame = NSRect(x: 192, y: 8, width: 152, height: 52)

        let voiceDecisionWidth: CGFloat = 336
        let voiceDecisionHeight: CGFloat = 70
        voiceRecognitionDecisionView.frame = NSRect(
            x: (bounds.width - voiceDecisionWidth) / 2,
            y: promptY - voiceDecisionHeight - 42,
            width: voiceDecisionWidth,
            height: voiceDecisionHeight
        )
        setupVoiceRecognitionButton.frame = NSRect(x: 0, y: 8, width: 170, height: 52)
        skipVoiceRecognitionButton.frame = NSRect(x: 194, y: 8, width: 142, height: 52)

        let voiceEnrollmentWidth = min(bounds.width - 152, 760)
        let voiceEnrollmentHeight: CGFloat = 142
        voiceEnrollmentView.frame = NSRect(
            x: (bounds.width - voiceEnrollmentWidth) / 2,
            y: promptY - voiceEnrollmentHeight - 42,
            width: voiceEnrollmentWidth,
            height: voiceEnrollmentHeight
        )
        voiceEnrollmentStatusField.frame = NSRect(x: 20, y: 98, width: voiceEnrollmentWidth - 40, height: 24)
        let enrollmentButtonWidth: CGFloat = 128
        let enrollmentGap: CGFloat = 12
        let enrollmentButtonsWidth = (enrollmentButtonWidth * 3) + (enrollmentGap * 2)
        let enrollmentStartX = (voiceEnrollmentWidth - enrollmentButtonsWidth) / 2
        recordVoiceButton.frame = NSRect(x: enrollmentStartX, y: 26, width: enrollmentButtonWidth, height: 52)
        skipVoiceEnrollmentButton.frame = NSRect(
            x: recordVoiceButton.frame.maxX + enrollmentGap,
            y: 26,
            width: enrollmentButtonWidth,
            height: 52
        )
        continueVoiceEnrollmentButton.frame = NSRect(
            x: skipVoiceEnrollmentButton.frame.maxX + enrollmentGap,
            y: 26,
            width: enrollmentButtonWidth,
            height: 52
        )

        let decisionWidth: CGFloat = 276
        let decisionHeight: CGFloat = 70
        deviceDecisionView.frame = NSRect(
            x: (bounds.width - decisionWidth) / 2,
            y: promptY - decisionHeight - 42,
            width: decisionWidth,
            height: decisionHeight
        )
        yesDevicesButton.frame = NSRect(x: 0, y: 8, width: 126, height: 52)
        noDevicesButton.frame = NSRect(x: 150, y: 8, width: 126, height: 52)

        let selectionWidth = min(bounds.width - 152, 900)
        let selectionHeight = deviceSelectionHeight()
        deviceSelectionView.frame = NSRect(
            x: (bounds.width - selectionWidth) / 2,
            y: promptY - selectionHeight - 42,
            width: selectionWidth,
            height: selectionHeight
        )
        layoutDeviceButtons(width: selectionWidth)
        layoutRemoteFields(width: selectionWidth)

        let pairingWidth: CGFloat = 360
        let pairingHeight: CGFloat = 342
        pairingView.frame = NSRect(
            x: (bounds.width - pairingWidth) / 2,
            y: promptY - pairingHeight - 30,
            width: pairingWidth,
            height: pairingHeight
        )
        qrImageView.frame = NSRect(x: 70, y: 92, width: 220, height: 220)
        pairingDetailField.frame = NSRect(x: 20, y: 58, width: 320, height: 22)
        donePairingButton.frame = NSRect(x: 116, y: 0, width: 128, height: 48)
    }

    private func setup() {
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
        hideInput()
        hideStepControls(animated: false)
        Task { [weak self] in
            guard let self else { return }
            _ = await liveSpeech.requestAuthorization()
        }
    }

    private var promptShadow: NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.96)
        shadow.shadowBlurRadius = 30
        shadow.shadowOffset = NSSize(width: 0, height: -16)
        return shadow
    }

    private var inputShadow: NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.82)
        shadow.shadowBlurRadius = 22
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        return shadow
    }

    private func startPrompt() {
        streamTask?.cancel()
        acceptsLiveSpeechInput = false
        liveSpeech.cancel()
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
            lastHandledFinalVoiceInput = ""
            acceptsLiveSpeechInput = true
            await beginLiveSpeechCapture(stopCurrentSpeech: false)
            await promptSpeechTask.value
        }
    }

    private func refreshDiscoveredDevices() async {
        let devices = await deviceDiscovery.discover()
        guard !Task.isCancelled else { return }
        store.mergeDiscoveredDevices(devices)
    }

    private func showInputIfNeeded() {
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
        case .askingDeviceSetup, .choosingDevices, .showingPairingQRCode:
            hideInput()
            hideStepControls(animated: false)
        case .complete:
            hideInput()
            hideStepControls(animated: true)
        }
    }

    private func showInput(placeholder: String, value: String) {
        inputField.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.56),
                .font: NSFont.systemFont(ofSize: 32, weight: .medium)
            ]
        )
        inputField.stringValue = value
        inputField.isHidden = false
        inputLine.isHidden = false
        window?.makeFirstResponder(inputField)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            window?.makeFirstResponder(inputField)
            (inputField.currentEditor() as? NSTextView)?.insertionPointColor = .white
        }
    }

    private func hideInput() {
        inputField.isHidden = true
        inputLine.isHidden = true
    }

    private func setupVoiceControls() {
        voiceControlsView.wantsLayer = true
        voiceControlsView.layer?.cornerRadius = 8
        voiceControlsView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
        voiceControlsView.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        voiceControlsView.layer?.borderWidth = 1
        voiceControlsView.shadow = inputShadow
        addSubview(voiceControlsView)

        voicePopup.font = .systemFont(ofSize: 22, weight: .medium)
        voicePopup.isBordered = false
        voicePopup.target = self
        voicePopup.action = #selector(voicePopupChanged(_:))
        voiceControlsView.addSubview(voicePopup)

        configureVoiceButton(previewVoiceButton, action: #selector(previewVoice(_:)))
        configureVoiceButton(selectVoiceButton, action: #selector(selectVoice(_:)))
        voiceControlsView.addSubview(previewVoiceButton)
        voiceControlsView.addSubview(selectVoiceButton)
        reloadVoiceChoices()
    }

    private func setupAgentNameDecisionControls() {
        configureFloatingControlContainer(agentNameDecisionView)
        addSubview(agentNameDecisionView)
        configureVoiceButton(keepAgentNameButton, action: #selector(keepAgentName(_:)))
        configureVoiceButton(renameAgentButton, action: #selector(renameAgent(_:)))
        agentNameDecisionView.addSubview(keepAgentNameButton)
        agentNameDecisionView.addSubview(renameAgentButton)
    }

    private func setupVoiceRecognitionControls() {
        configureFloatingControlContainer(voiceRecognitionDecisionView)
        addSubview(voiceRecognitionDecisionView)
        configureVoiceButton(setupVoiceRecognitionButton, action: #selector(setupVoiceRecognition(_:)))
        configureVoiceButton(skipVoiceRecognitionButton, action: #selector(skipVoiceRecognition(_:)))
        voiceRecognitionDecisionView.addSubview(setupVoiceRecognitionButton)
        voiceRecognitionDecisionView.addSubview(skipVoiceRecognitionButton)

        configureFloatingControlContainer(voiceEnrollmentView)
        addSubview(voiceEnrollmentView)

        voiceEnrollmentStatusField.font = .systemFont(ofSize: 18, weight: .medium)
        voiceEnrollmentStatusField.textColor = NSColor.white.withAlphaComponent(0.78)
        voiceEnrollmentStatusField.alignment = .center
        voiceEnrollmentStatusField.lineBreakMode = .byTruncatingTail
        voiceEnrollmentStatusField.shadow = inputShadow
        voiceEnrollmentView.addSubview(voiceEnrollmentStatusField)

        configureVoiceButton(recordVoiceButton, action: #selector(recordVoiceSample(_:)))
        configureVoiceButton(skipVoiceEnrollmentButton, action: #selector(skipVoiceEnrollment(_:)))
        configureVoiceButton(continueVoiceEnrollmentButton, action: #selector(continueVoiceEnrollment(_:)))
        voiceEnrollmentView.addSubview(recordVoiceButton)
        voiceEnrollmentView.addSubview(skipVoiceEnrollmentButton)
        voiceEnrollmentView.addSubview(continueVoiceEnrollmentButton)
        reloadVoiceEnrollmentControls()
    }

    private func configureVoiceButton(_ button: NSButton, action: Selector) {
        button.target = self
        button.action = action
        button.isBordered = false
        button.font = .systemFont(ofSize: 18, weight: .semibold)
        button.contentTintColor = .white
        button.keyEquivalent = ""
        button.refusesFirstResponder = true
        button.focusRingType = .none
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
    }

    private func setupDeviceDecisionControls() {
        configureFloatingControlContainer(deviceDecisionView)
        addSubview(deviceDecisionView)
        configureVoiceButton(yesDevicesButton, action: #selector(chooseOtherDevices(_:)))
        configureVoiceButton(noDevicesButton, action: #selector(skipOtherDevices(_:)))
        deviceDecisionView.addSubview(yesDevicesButton)
        deviceDecisionView.addSubview(noDevicesButton)
    }

    private func setupDeviceSelectionControls() {
        configureFloatingControlContainer(deviceSelectionView)
        addSubview(deviceSelectionView)

        for device in store.availableDeviceKinds {
            let button = DetourDeviceOptionButton(device: device)
            button.identifier = NSUserInterfaceItemIdentifier(device.rawValue)
            button.target = self
            button.action = #selector(toggleDevice(_:))
            deviceButtons[device] = button
            deviceSelectionView.addSubview(button)
        }

        configureRemoteField(remoteHostField, identifier: "remoteHost", placeholder: "remote host")
        configureRemoteField(remoteUserField, identifier: "remoteUser", placeholder: "ssh user")
        configureRemoteField(remotePortField, identifier: "remotePort", placeholder: "22")
        deviceSelectionView.addSubview(remoteHostField)
        deviceSelectionView.addSubview(remoteUserField)
        deviceSelectionView.addSubview(remotePortField)

        configureVoiceButton(continueDevicesButton, action: #selector(continueDevices(_:)))
        deviceSelectionView.addSubview(continueDevicesButton)
        reloadDeviceChoices()
    }

    private func configureRemoteField(_ field: DetourInputField, identifier: String, placeholder: String) {
        field.identifier = NSUserInterfaceItemIdentifier(identifier)
        field.delegate = self
        field.font = .systemFont(ofSize: 18, weight: .medium)
        field.textColor = .white
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.52),
                .font: NSFont.systemFont(ofSize: 18, weight: .medium)
            ]
        )
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .center
        field.wantsLayer = true
        field.layer?.cornerRadius = 8
        field.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.2).cgColor
    }

    private func setupPairingControls() {
        configureFloatingControlContainer(pairingView)
        addSubview(pairingView)

        qrImageView.imageAlignment = .alignCenter
        qrImageView.imageScaling = .scaleProportionallyUpOrDown
        qrImageView.wantsLayer = true
        qrImageView.layer?.cornerRadius = 8
        qrImageView.layer?.backgroundColor = NSColor.white.cgColor
        pairingView.addSubview(qrImageView)

        pairingDetailField.font = .systemFont(ofSize: 13, weight: .medium)
        pairingDetailField.textColor = NSColor.white.withAlphaComponent(0.72)
        pairingDetailField.alignment = .center
        pairingDetailField.lineBreakMode = .byTruncatingMiddle
        pairingView.addSubview(pairingDetailField)

        configureVoiceButton(donePairingButton, action: #selector(donePairing(_:)))
        pairingView.addSubview(donePairingButton)
    }

    private func configureFloatingControlContainer(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        view.layer?.borderWidth = 1
        view.shadow = inputShadow
    }

    private func layoutDeviceButtons(width: CGFloat) {
        let columns = 4
        let horizontalPadding: CGFloat = 18
        let columnGap: CGFloat = 12
        let tileHeight: CGFloat = 72
        let rowGap: CGFloat = 12
        let columnWidth = (width - (horizontalPadding * 2) - (CGFloat(columns - 1) * columnGap)) / CGFloat(columns)
        let panelHeight = deviceSelectionHeight()
        let firstRowY = panelHeight - 18 - tileHeight

        for (index, device) in store.availableDeviceKinds.enumerated() {
            let row = index / columns
            let column = index % columns
            deviceButtons[device]?.frame = NSRect(
                x: horizontalPadding + CGFloat(column) * (columnWidth + columnGap),
                y: firstRowY - CGFloat(row) * (tileHeight + rowGap),
                width: columnWidth,
                height: tileHeight
            )
        }

        continueDevicesButton.frame = NSRect(x: width - 148, y: 12, width: 128, height: 48)
    }

    private func deviceSelectionHeight() -> CGFloat {
        let columns = 4
        let rows = max(1, Int(ceil(Double(store.availableDeviceKinds.count) / Double(columns))))
        let tileArea = CGFloat(rows) * 72 + CGFloat(max(0, rows - 1)) * 12
        let remoteFieldsHeight: CGFloat = store.selectedDeviceKinds.contains(.remoteDetour) ? 112 : 0
        return 18 + tileArea + remoteFieldsHeight + 76
    }

    private func layoutRemoteFields(width: CGFloat) {
        let showRemote = store.selectedDeviceKinds.contains(.remoteDetour)
        remoteHostField.isHidden = !showRemote
        remoteUserField.isHidden = !showRemote
        remotePortField.isHidden = !showRemote

        guard showRemote else { return }

        let padding: CGFloat = 20
        let gap: CGFloat = 12
        let portWidth: CGFloat = 88
        let userWidth: CGFloat = 178
        let hostWidth = width - (padding * 2) - (gap * 2) - userWidth - portWidth
        remoteHostField.frame = NSRect(x: padding, y: 78, width: hostWidth, height: 42)
        remoteUserField.frame = NSRect(x: remoteHostField.frame.maxX + gap, y: 78, width: userWidth, height: 42)
        remotePortField.frame = NSRect(x: remoteUserField.frame.maxX + gap, y: 78, width: portWidth, height: 42)
        continueDevicesButton.frame = NSRect(x: width - 148, y: 12, width: 128, height: 48)
    }

    private func reloadVoiceChoices() {
        voicePopup.removeAllItems()
        voicePopup.addItem(withTitle: "OmniVoice local")
        voicePopup.lastItem?.representedObject = "omnivoice-local"
        voicePopup.selectItem(at: 0)
    }

    private func reloadVoiceEnrollmentControls() {
        voiceEnrollmentStatusField.stringValue = voiceRecorder.statusText
        recordVoiceButton.title = voiceRecorder.isRecording ? "Stop" : "Record"
        continueVoiceEnrollmentButton.isEnabled = voiceRecorder.hasSample
        continueVoiceEnrollmentButton.alphaValue = voiceRecorder.hasSample ? 1 : 0.44
    }

    private func reloadDeviceChoices() {
        for (device, button) in deviceButtons {
            button.update(isSelected: store.selectedDeviceKinds.contains(device), title: store.title(for: device))
        }
        remoteHostField.stringValue = store.remoteHostDraft
        remoteUserField.stringValue = store.remoteUserDraft
        remotePortField.stringValue = store.remotePortDraft
        let remoteReady = !store.selectedDeviceKinds.contains(.remoteDetour)
            || !store.remoteHostDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        continueDevicesButton.isEnabled = !store.selectedDeviceKinds.isEmpty && remoteReady
        continueDevicesButton.alphaValue = continueDevicesButton.isEnabled ? 1 : 0.44
        needsLayout = true
    }

    private func reloadPairingView() {
        if store.pairingInfo == nil && store.pairingError == nil {
            store.continueToPairingQRCode()
        }

        qrImageView.image = store.pairingInfo?.qrImage
        if let host = store.pairingInfo?.host {
            pairingDetailField.stringValue = host
        } else {
            pairingDetailField.stringValue = store.pairingError ?? "Pairing unavailable"
        }
    }

    private func showControlsForCurrentStep() {
        switch store.step {
        case .askingAgentName:
            showAgentNameDecisionControls()
        case .choosingVoice:
            showVoiceControls()
        case .askingVoiceRecognition:
            showVoiceRecognitionDecisionControls()
        case .enrollingVoice:
            reloadVoiceEnrollmentControls()
            showVoiceEnrollmentControls()
        case .askingDeviceSetup:
            showDeviceDecisionControls()
        case .choosingDevices:
            reloadDeviceChoices()
            showDeviceSelectionControls()
        case .showingPairingQRCode:
            reloadPairingView()
            showPairingControls()
        case .askingName, .renamingAgent, .settingWakeWord, .complete:
            break
        }
    }

    private func showAgentNameDecisionControls() {
        guard !agentNameDecisionVisible else { return }
        agentNameDecisionVisible = true
        animateControlIn(agentNameDecisionView)
    }

    private func showVoiceControls() {
        guard !voiceControlsVisible else { return }
        voiceControlsVisible = true
        voiceControlsView.isHidden = false
        voiceControlsView.alphaValue = 0
        let targetFrame = voiceControlsView.frame
        voiceControlsView.frame = targetFrame.offsetBy(dx: 0, dy: -18)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.34
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            voiceControlsView.animator().alphaValue = 1
            voiceControlsView.animator().frame = targetFrame
        }
    }

    private func showVoiceRecognitionDecisionControls() {
        guard !voiceRecognitionDecisionVisible else { return }
        voiceRecognitionDecisionVisible = true
        animateControlIn(voiceRecognitionDecisionView)
    }

    private func showVoiceEnrollmentControls() {
        guard !voiceEnrollmentVisible else { return }
        voiceEnrollmentVisible = true
        animateControlIn(voiceEnrollmentView)
    }

    private func showDeviceDecisionControls() {
        guard !deviceDecisionVisible else { return }
        deviceDecisionVisible = true
        animateControlIn(deviceDecisionView)
    }

    private func showDeviceSelectionControls() {
        guard !deviceSelectionVisible else { return }
        deviceSelectionVisible = true
        animateControlIn(deviceSelectionView)
    }

    private func showPairingControls() {
        guard !pairingVisible else { return }
        pairingVisible = true
        animateControlIn(pairingView)
    }

    private func animateControlIn(_ view: NSView) {
        view.isHidden = false
        view.alphaValue = 0
        let targetFrame = view.frame
        view.frame = targetFrame.offsetBy(dx: 0, dy: -18)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.34
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            view.animator().alphaValue = 1
            view.animator().frame = targetFrame
        }
    }

    private func hideStepControls(animated: Bool) {
        hideAgentNameDecisionControls(animated: animated)
        hideVoiceControls(animated: animated)
        hideVoiceRecognitionDecisionControls(animated: animated)
        hideVoiceEnrollmentControls(animated: animated)
        hideDeviceDecisionControls(animated: animated)
        hideDeviceSelectionControls(animated: animated)
        hidePairingControls(animated: animated)
    }

    private func hideAgentNameDecisionControls(animated: Bool) {
        guard !agentNameDecisionView.isHidden || agentNameDecisionVisible else { return }
        agentNameDecisionVisible = false
        hideControl(agentNameDecisionView, animated: animated)
    }

    private func hideVoiceControls(animated: Bool) {
        guard !voiceControlsView.isHidden || voiceControlsVisible else { return }
        voiceControlsVisible = false
        hideControl(voiceControlsView, animated: animated)
    }

    private func hideVoiceRecognitionDecisionControls(animated: Bool) {
        guard !voiceRecognitionDecisionView.isHidden || voiceRecognitionDecisionVisible else { return }
        voiceRecognitionDecisionVisible = false
        hideControl(voiceRecognitionDecisionView, animated: animated)
    }

    private func hideVoiceEnrollmentControls(animated: Bool) {
        guard !voiceEnrollmentView.isHidden || voiceEnrollmentVisible else { return }
        voiceEnrollmentVisible = false
        hideControl(voiceEnrollmentView, animated: animated)
    }

    private func hideDeviceDecisionControls(animated: Bool) {
        guard !deviceDecisionView.isHidden || deviceDecisionVisible else { return }
        deviceDecisionVisible = false
        hideControl(deviceDecisionView, animated: animated)
    }

    private func hideDeviceSelectionControls(animated: Bool) {
        guard !deviceSelectionView.isHidden || deviceSelectionVisible else { return }
        deviceSelectionVisible = false
        hideControl(deviceSelectionView, animated: animated)
    }

    private func hidePairingControls(animated: Bool) {
        guard !pairingView.isHidden || pairingVisible else { return }
        pairingVisible = false
        hideControl(pairingView, animated: animated)
    }

    private func hideControl(_ view: NSView, animated: Bool) {
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                view.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    _ = self
                    view.isHidden = true
                }
            }
        } else {
            view.alphaValue = 0
            view.isHidden = true
        }
    }

    private func beginLiveSpeechCapture(stopCurrentSpeech: Bool) async {
        guard stepAllowsLiveSpeech, !liveSpeech.isListening else { return }
        guard await liveSpeech.requestAuthorization() == .authorized else { return }
        if stopCurrentSpeech {
            speech.stop()
        }
        lastHandledFinalVoiceInput = ""
        try? await liveSpeech.start()
    }

    private var stepAllowsLiveSpeech: Bool {
        switch store.step {
        case .complete:
            false
        case .askingName, .askingAgentName, .renamingAgent, .choosingVoice, .askingVoiceRecognition,
             .enrollingVoice, .settingWakeWord, .askingDeviceSetup, .choosingDevices, .showingPairingQRCode:
            true
        }
    }

    private func applyPartialVoiceInput(_ transcript: String) {
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
             .askingDeviceSetup, .showingPairingQRCode, .complete:
            break
        }
    }

    private func handleFinalVoiceInput(_ transcript: String) {
        guard acceptsLiveSpeechInput else { return }
        let value = cleanedSpokenValue(transcript)
        guard !value.isEmpty, consumeFinalVoiceInput(value) else { return }
        let command = value.lowercased()
        guard !isCurrentPromptEcho(command) else { return }

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

    private func recordVoiceSampleFromSpeech() {
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

    private func previewVoiceFromSpeech() {
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

    private func consumeFinalVoiceInput(_ value: String) -> Bool {
        let fingerprint = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard fingerprint != lastHandledFinalVoiceInput else { return false }
        lastHandledFinalVoiceInput = fingerprint
        return true
    }

    private func isCurrentPromptEcho(_ value: String) -> Bool {
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

    private func canonicalSpeechWords(_ value: String) -> [String] {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private func applyRemoteDrafts(from value: String) {
        let command = value.lowercased()
        guard store.selectedDeviceKinds.contains(.remoteDetour) else { return }
        if command.contains(".") || command.contains(":") {
            store.remoteHostDraft = value
            remoteHostField.stringValue = value
        }
    }

    private var canContinueDeviceSelectionFromSpeech: Bool {
        guard !store.selectedDeviceKinds.isEmpty else { return false }
        if store.selectedDeviceKinds.contains(.remoteDetour) {
            return !store.remoteHostDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private func applyDeviceChoices(from command: String) {
        for device in store.availableDeviceKinds where commandMentions(device, in: command) {
            if !store.selectedDeviceKinds.contains(device) {
                store.toggleDevice(device)
            }
        }
    }

    private func commandMentions(_ device: DetourDeviceKind, in command: String) -> Bool {
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

    private func isContinueCommand(_ command: String) -> Bool {
        commandContains(command, ["continue", "done", "next", "save", "submit", "that's it", "that is it"])
    }

    private func submit() {
        switch store.step {
        case .askingName:
            store.userNameDraft = inputField.stringValue
            store.submitName()
        case .askingAgentName:
            store.agentNameDraft = inputField.stringValue
            store.submitAgentDecision()
        case .renamingAgent:
            store.agentNameDraft = inputField.stringValue
            store.submitAgentName()
        case .choosingVoice:
            store.confirmVoice()
        case .settingWakeWord:
            store.wakeWordDraft = inputField.stringValue
            store.submitWakeWord()
        case .askingVoiceRecognition:
            store.skipVoiceEnrollment()
        case .enrollingVoice:
            if voiceRecorder.hasSample {
                store.completeVoiceEnrollment()
            }
        case .askingDeviceSetup:
            store.setWantsOtherAppleDevices(false)
        case .choosingDevices:
            store.continueToPairingQRCode()
        case .showingPairingQRCode:
            store.finishCurrentDeviceSetup()
        case .complete:
            break
        }

        startPrompt()
    }

    private func promptHeight(for width: CGFloat) -> CGFloat {
        let value = promptField.stringValue.isEmpty ? " " : promptField.stringValue
        let font = promptField.font ?? .systemFont(ofSize: 58, weight: .semibold)
        let rect = (value as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return max(96, ceil(rect.height) + 22)
    }

    func controlTextDidChange(_ obj: Notification) {
        if let field = obj.object as? NSTextField,
           let identifier = field.identifier?.rawValue {
            switch identifier {
            case "remoteHost":
                store.remoteHostDraft = field.stringValue
                reloadDeviceChoices()
                return
            case "remoteUser":
                store.remoteUserDraft = field.stringValue
                return
            case "remotePort":
                store.remotePortDraft = field.stringValue
                return
            default:
                break
            }
        }

        switch store.step {
        case .askingName:
            store.userNameDraft = inputField.stringValue
        case .askingAgentName, .renamingAgent:
            store.agentNameDraft = inputField.stringValue
        case .settingWakeWord:
            store.wakeWordDraft = inputField.stringValue
        case .choosingVoice, .askingVoiceRecognition, .enrollingVoice,
             .askingDeviceSetup, .choosingDevices, .showingPairingQRCode:
            break
        case .complete:
            break
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            guard isCurrentKeyDown(36, 76) else { return true }
            submit()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            guard isCurrentKeyDown(53) else { return true }
            exit()
            return true
        default:
            return false
        }
    }

    private func isCurrentKeyDown(_ keyCodes: UInt16...) -> Bool {
        guard let event = NSApp.currentEvent, event.type == .keyDown else { return false }
        return keyCodes.contains(event.keyCode)
    }

    @objc private func voicePopupChanged(_ sender: NSPopUpButton) {
        guard let identifier = sender.selectedItem?.representedObject as? String else { return }
        store.selectVoice(identifier: identifier)
    }

    @objc private func previewVoice(_ sender: NSButton) {
        speech.speak(store.voicePreviewText, speech: store.config.speech)
    }

    @objc private func selectVoice(_ sender: NSButton) {
        store.confirmVoice()
        startPrompt()
    }

    @objc private func keepAgentName(_ sender: NSButton) {
        store.acceptDefaultAgentName()
        startPrompt()
    }

    @objc private func renameAgent(_ sender: NSButton) {
        store.startRenamingAgent()
        startPrompt()
    }

    @objc private func setupVoiceRecognition(_ sender: NSButton) {
        store.beginVoiceRecognitionSetup()
        voiceRecorder.reset()
        startPrompt()
    }

    @objc private func skipVoiceRecognition(_ sender: NSButton) {
        store.skipVoiceEnrollment()
        startPrompt()
    }

    @objc private func recordVoiceSample(_ sender: NSButton) {
        if voiceRecorder.isRecording {
            voiceRecorder.stopRecording()
            reloadVoiceEnrollmentControls()
            return
        }

        speech.stop()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await voiceRecorder.startRecording(to: store.voiceEnrollmentSampleURL())
            } catch {
                voiceRecorder.reset()
            }
            reloadVoiceEnrollmentControls()
        }
    }

    @objc private func skipVoiceEnrollment(_ sender: NSButton) {
        voiceRecorder.reset()
        store.skipVoiceEnrollment()
        startPrompt()
    }

    @objc private func continueVoiceEnrollment(_ sender: NSButton) {
        guard voiceRecorder.hasSample else { return }
        store.completeVoiceEnrollment()
        startPrompt()
    }

    @objc private func chooseOtherDevices(_ sender: NSButton) {
        store.setWantsOtherAppleDevices(true)
        startPrompt()
    }

    @objc private func skipOtherDevices(_ sender: NSButton) {
        store.setWantsOtherAppleDevices(false)
        startPrompt()
    }

    @objc private func toggleDevice(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue,
              let device = DetourDeviceKind(rawValue: rawValue) else {
            return
        }

        store.toggleDevice(device)
        reloadDeviceChoices()
    }

    @objc private func continueDevices(_ sender: NSButton) {
        guard continueDevicesButton.isEnabled else { return }
        store.continueToPairingQRCode()
        startPrompt()
    }

    @objc private func donePairing(_ sender: NSButton) {
        store.finishCurrentDeviceSetup()
        startPrompt()
    }
}

private final class DetourDeviceOptionButton: NSButton {
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let checkmarkView = NSImageView()

    override var isFlipped: Bool { true }

    init(device: DetourDeviceKind) {
        super.init(frame: .zero)
        title = ""
        isBordered = false
        setButtonType(.toggle)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        toolTip = device.displayName

        iconView.image = device.symbolImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
        addSubview(iconView)

        titleField.stringValue = device.displayName
        titleField.font = .systemFont(ofSize: 14, weight: .semibold)
        titleField.textColor = .white.withAlphaComponent(0.82)
        titleField.alignment = .center
        titleField.maximumNumberOfLines = 2
        titleField.lineBreakMode = .byWordWrapping
        addSubview(titleField)

        checkmarkView.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        checkmarkView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .bold)
        checkmarkView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(checkmarkView)

        update(isSelected: false, title: device.displayName)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        iconView.frame = NSRect(x: (bounds.width - 34) / 2, y: 12, width: 34, height: 30)
        titleField.frame = NSRect(x: 8, y: 47, width: bounds.width - 16, height: 20)
        checkmarkView.frame = NSRect(x: bounds.width - 24, y: 8, width: 16, height: 16)
    }

    func update(isSelected: Bool, title: String) {
        titleField.stringValue = title
        state = isSelected ? .on : .off
        layer?.backgroundColor = (isSelected ? NSColor.white.withAlphaComponent(0.22) : NSColor.black.withAlphaComponent(0.2)).cgColor
        layer?.borderColor = (isSelected ? NSColor.white.withAlphaComponent(0.54) : NSColor.white.withAlphaComponent(0.16)).cgColor
        iconView.contentTintColor = isSelected ? .white : NSColor.white.withAlphaComponent(0.58)
        titleField.textColor = isSelected ? .white : NSColor.white.withAlphaComponent(0.7)
        checkmarkView.isHidden = !isSelected
        checkmarkView.contentTintColor = .white
    }
}

private final class DetourInputField: NSTextField {
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
}
