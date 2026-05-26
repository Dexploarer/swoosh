// DetourOnboardingContentViewVisibility.swift — Detour onboarding view slice (0.5A)

import AppKit
import QuartzCore

extension DetourOnboardingContentView {
    func showControlsForCurrentStep() {
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
        case .askingPersonalizationScan:
            startPersonalizationButton.title = "Scan"
            skipPersonalizationButton.title = "Later"
            showPersonalizationDecisionControls()
        case .askingCredentialInheritance:
            startPersonalizationButton.title = "Allow"
            skipPersonalizationButton.title = "No"
            showPersonalizationDecisionControls()
        case .runningPersonalizationScan:
            reloadPersonalizationViews()
            showPersonalizationScanControls()
        case .reviewingPersonalizationScan:
            reloadPersonalizationViews()
            showPersonalizationReviewControls()
        case .askingName, .renamingAgent, .settingWakeWord, .complete:
            break
        }
    }

    func showAgentNameDecisionControls() {
        guard !agentNameDecisionVisible else { return }
        agentNameDecisionVisible = true
        animateControlIn(agentNameDecisionView)
    }

    func showVoiceControls() {
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

    func showVoiceRecognitionDecisionControls() {
        guard !voiceRecognitionDecisionVisible else { return }
        voiceRecognitionDecisionVisible = true
        animateControlIn(voiceRecognitionDecisionView)
    }

    func showVoiceEnrollmentControls() {
        guard !voiceEnrollmentVisible else { return }
        voiceEnrollmentVisible = true
        animateControlIn(voiceEnrollmentView)
    }

    func showDeviceDecisionControls() {
        guard !deviceDecisionVisible else { return }
        deviceDecisionVisible = true
        animateControlIn(deviceDecisionView)
    }

    func showDeviceSelectionControls() {
        guard !deviceSelectionVisible else { return }
        deviceSelectionVisible = true
        animateControlIn(deviceSelectionView)
    }

    func showPairingControls() {
        guard !pairingVisible else { return }
        pairingVisible = true
        animateControlIn(pairingView)
    }

    func showPersonalizationDecisionControls() {
        guard !personalizationDecisionVisible else { return }
        personalizationDecisionVisible = true
        animateControlIn(personalizationDecisionView)
    }

    func showPersonalizationScanControls() {
        guard !personalizationScanVisible else { return }
        personalizationScanVisible = true
        animateControlIn(personalizationScanView)
    }

    func showPersonalizationReviewControls() {
        guard !personalizationReviewVisible else { return }
        personalizationReviewVisible = true
        animateControlIn(personalizationReviewView)
    }

    func animateControlIn(_ view: NSView) {
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

    func hideStepControls(animated: Bool) {
        hideAgentNameDecisionControls(animated: animated)
        hideVoiceControls(animated: animated)
        hideVoiceRecognitionDecisionControls(animated: animated)
        hideVoiceEnrollmentControls(animated: animated)
        hideDeviceDecisionControls(animated: animated)
        hideDeviceSelectionControls(animated: animated)
        hidePairingControls(animated: animated)
        hidePersonalizationDecisionControls(animated: animated)
        hidePersonalizationScanControls(animated: animated)
        hidePersonalizationReviewControls(animated: animated)
    }

    func hideAgentNameDecisionControls(animated: Bool) {
        guard !agentNameDecisionView.isHidden || agentNameDecisionVisible else { return }
        agentNameDecisionVisible = false
        hideControl(agentNameDecisionView, animated: animated)
    }

    func hideVoiceControls(animated: Bool) {
        guard !voiceControlsView.isHidden || voiceControlsVisible else { return }
        voiceControlsVisible = false
        hideControl(voiceControlsView, animated: animated)
    }

    func hideVoiceRecognitionDecisionControls(animated: Bool) {
        guard !voiceRecognitionDecisionView.isHidden || voiceRecognitionDecisionVisible else { return }
        voiceRecognitionDecisionVisible = false
        hideControl(voiceRecognitionDecisionView, animated: animated)
    }

    func hideVoiceEnrollmentControls(animated: Bool) {
        guard !voiceEnrollmentView.isHidden || voiceEnrollmentVisible else { return }
        voiceEnrollmentVisible = false
        hideControl(voiceEnrollmentView, animated: animated)
    }

    func hideDeviceDecisionControls(animated: Bool) {
        guard !deviceDecisionView.isHidden || deviceDecisionVisible else { return }
        deviceDecisionVisible = false
        hideControl(deviceDecisionView, animated: animated)
    }

    func hideDeviceSelectionControls(animated: Bool) {
        guard !deviceSelectionView.isHidden || deviceSelectionVisible else { return }
        deviceSelectionVisible = false
        hideControl(deviceSelectionView, animated: animated)
    }

    func hidePairingControls(animated: Bool) {
        guard !pairingView.isHidden || pairingVisible else { return }
        pairingVisible = false
        hideControl(pairingView, animated: animated)
    }

    func hidePersonalizationDecisionControls(animated: Bool) {
        guard !personalizationDecisionView.isHidden || personalizationDecisionVisible else { return }
        personalizationDecisionVisible = false
        hideControl(personalizationDecisionView, animated: animated)
    }

    func hidePersonalizationScanControls(animated: Bool) {
        guard !personalizationScanView.isHidden || personalizationScanVisible else { return }
        personalizationScanVisible = false
        hideControl(personalizationScanView, animated: animated)
    }

    func hidePersonalizationReviewControls(animated: Bool) {
        guard !personalizationReviewView.isHidden || personalizationReviewVisible else { return }
        personalizationReviewVisible = false
        hideControl(personalizationReviewView, animated: animated)
    }

    func hideControl(_ view: NSView, animated: Bool) {
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

}
