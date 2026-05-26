// DetourOnboardingContentViewControls.swift — Detour onboarding view slice (0.5A)

import AppKit
import QuartzCore

extension DetourOnboardingContentView {
    func setupVoiceControls() {
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

    func setupNavigationControls() {
        backButton.target = self
        backButton.action = #selector(goBack(_:))
        backButton.isBordered = false
        backButton.imagePosition = .imageOnly
        backButton.imageScaling = .scaleProportionallyDown
        backButton.contentTintColor = NSColor.white.withAlphaComponent(0.86)
        backButton.toolTip = "Back"
        backButton.refusesFirstResponder = true
        backButton.focusRingType = .none
        backButton.wantsLayer = true
        backButton.layer?.cornerRadius = 8
        backButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.24).cgColor
        backButton.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        backButton.layer?.borderWidth = 1
        backButton.shadow = inputShadow
        backButton.setAccessibilityLabel("Back")
        addSubview(backButton)
    }

    func reloadNavigationControls() {
        backButton.isHidden = !store.canGoBack
        backButton.alphaValue = store.canGoBack ? 1 : 0
    }

    func setupAgentNameDecisionControls() {
        configureFloatingControlContainer(agentNameDecisionView)
        addSubview(agentNameDecisionView)
        configureVoiceButton(keepAgentNameButton, action: #selector(keepAgentName(_:)))
        configureVoiceButton(renameAgentButton, action: #selector(renameAgent(_:)))
        agentNameDecisionView.addSubview(keepAgentNameButton)
        agentNameDecisionView.addSubview(renameAgentButton)
    }

    func setupVoiceRecognitionControls() {
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

    func configureVoiceButton(_ button: NSButton, action: Selector) {
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

    func setupDeviceDecisionControls() {
        configureFloatingControlContainer(deviceDecisionView)
        addSubview(deviceDecisionView)
        configureVoiceButton(yesDevicesButton, action: #selector(chooseOtherDevices(_:)))
        configureVoiceButton(noDevicesButton, action: #selector(skipOtherDevices(_:)))
        deviceDecisionView.addSubview(yesDevicesButton)
        deviceDecisionView.addSubview(noDevicesButton)
    }

    func setupDeviceSelectionControls() {
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

    func configureRemoteField(_ field: DetourInputField, identifier: String, placeholder: String) {
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

    func setupPairingControls() {
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

    func setupPersonalizationControls() {
        configureFloatingControlContainer(personalizationDecisionView)
        addSubview(personalizationDecisionView)
        configureVoiceButton(startPersonalizationButton, action: #selector(startPersonalization(_:)))
        configureVoiceButton(skipPersonalizationButton, action: #selector(skipPersonalization(_:)))
        personalizationDecisionView.addSubview(startPersonalizationButton)
        personalizationDecisionView.addSubview(skipPersonalizationButton)

        configureFloatingControlContainer(personalizationScanView)
        addSubview(personalizationScanView)
        personalizationProgressIndicator.isIndeterminate = false
        personalizationProgressIndicator.minValue = 0
        personalizationProgressIndicator.maxValue = 1
        personalizationProgressIndicator.doubleValue = 0
        personalizationProgressIndicator.controlSize = .small
        personalizationProgressIndicator.style = .bar
        personalizationProgressIndicator.wantsLayer = true
        personalizationScanView.addSubview(personalizationProgressIndicator)

        configurePersonalizationLabel(personalizationProgressField, fontSize: 18, weight: .semibold)
        configurePersonalizationLabel(personalizationTipField, fontSize: 15, weight: .medium)
        personalizationTipField.textColor = NSColor.white.withAlphaComponent(0.66)
        personalizationScanView.addSubview(personalizationProgressField)
        personalizationScanView.addSubview(personalizationTipField)

        configureFloatingControlContainer(personalizationReviewView)
        addSubview(personalizationReviewView)
        setupPersonalizationReviewContent()
        personalizationReviewView.addSubview(setupInsightSearchField)
        personalizationReviewView.addSubview(personalizationReviewScrollView)

        configureVoiceButton(continuePersonalizationButton, action: #selector(continuePersonalization(_:)))
        personalizationReviewView.addSubview(continuePersonalizationButton)
        reloadPersonalizationViews()
    }

    func configurePersonalizationLabel(_ field: NSTextField, fontSize: CGFloat, weight: NSFont.Weight) {
        field.font = .systemFont(ofSize: fontSize, weight: weight)
        field.textColor = NSColor.white.withAlphaComponent(0.82)
        field.alignment = .center
        field.lineBreakMode = .byWordWrapping
        field.shadow = inputShadow
    }

    func configureFloatingControlContainer(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        view.layer?.borderWidth = 1
        view.shadow = inputShadow
    }

    func setupPersonalizationReviewContent() {
        setupInsightSearchField.identifier = NSUserInterfaceItemIdentifier("setupInsightSearch")
        setupInsightSearchField.delegate = self
        setupInsightSearchField.placeholderString = "Search setup"
        setupInsightSearchField.font = .systemFont(ofSize: 14, weight: .medium)
        setupInsightSearchField.textColor = .white
        setupInsightSearchField.focusRingType = .default
        personalizationReviewScrollView.drawsBackground = false
        personalizationReviewScrollView.borderType = .noBorder
        personalizationReviewScrollView.hasVerticalScroller = true
        personalizationReviewScrollView.autohidesScrollers = true
        personalizationReviewScrollView.documentView = personalizationReviewContentView
    }

}
