// DetourOnboardingContentView.swift — native frosted Detour onboarding input (0.5A)

import AppKit
import QuartzCore

@MainActor
final class DetourOnboardingContentView: NSView, NSTextFieldDelegate, NSSearchFieldDelegate {
    let store: OnboardingStore
    let speech: DetourSpeechService
    let exit: () -> Void
    let blurView = NSVisualEffectView()
    let promptField = NSTextField(labelWithString: "")
    let backButton = NSButton(
        image: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back") ?? NSImage(),
        target: nil,
        action: nil
    )
    let inputField = DetourInputField()
    let inputLine = NSView()
    let voiceControlsView = NSView()
    let voicePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let previewVoiceButton = NSButton(title: "Preview", target: nil, action: nil)
    let selectVoiceButton = NSButton(title: "Select", target: nil, action: nil)
    let agentNameDecisionView = NSView()
    let keepAgentNameButton = NSButton(title: "Keep Detour", target: nil, action: nil)
    let renameAgentButton = NSButton(title: "Rename", target: nil, action: nil)
    let voiceRecognitionDecisionView = NSView()
    let setupVoiceRecognitionButton = NSButton(title: "Set up voice", target: nil, action: nil)
    let skipVoiceRecognitionButton = NSButton(title: "Later", target: nil, action: nil)
    let voiceEnrollmentView = NSView()
    let voiceEnrollmentStatusField = NSTextField(labelWithString: "")
    let recordVoiceButton = NSButton(title: "Record", target: nil, action: nil)
    let skipVoiceEnrollmentButton = NSButton(title: "Skip", target: nil, action: nil)
    let continueVoiceEnrollmentButton = NSButton(title: "Continue", target: nil, action: nil)
    let deviceDecisionView = NSView()
    let yesDevicesButton = NSButton(title: "Yes", target: nil, action: nil)
    let noDevicesButton = NSButton(title: "Not now", target: nil, action: nil)
    let deviceSelectionView = NSView()
    var deviceButtons: [DetourDeviceKind: DetourDeviceOptionButton] = [:]
    let remoteHostField = DetourInputField()
    let remoteUserField = DetourInputField()
    let remotePortField = DetourInputField()
    let continueDevicesButton = NSButton(title: "Continue", target: nil, action: nil)
    let pairingView = NSView()
    let qrImageView = NSImageView()
    let pairingDetailField = NSTextField(labelWithString: "")
    let donePairingButton = NSButton(title: "Skip", target: nil, action: nil)
    let personalizationDecisionView = NSView()
    let startPersonalizationButton = NSButton(title: "Scan", target: nil, action: nil)
    let skipPersonalizationButton = NSButton(title: "Later", target: nil, action: nil)
    let personalizationScanView = NSView()
    let personalizationProgressIndicator = NSProgressIndicator()
    let personalizationProgressField = NSTextField(labelWithString: "")
    let personalizationTipField = NSTextField(labelWithString: "")
    let personalizationReviewView = NSView()
    let setupInsightSearchField = NSSearchField()
    let personalizationReviewScrollView = NSScrollView()
    let personalizationReviewContentView = DetourFlippedView()
    let continuePersonalizationButton = NSButton(title: "Continue", target: nil, action: nil)
    let voiceRecorder = DetourVoiceEnrollmentRecorder()
    let liveSpeech = DetourLiveSpeechRecognizer()
    let deviceDiscovery = DetourDeviceDiscovery()
    var streamTask: Task<Void, Never>?
    var voiceRecordingTask: Task<Void, Never>?
    var agentNameDecisionVisible = false
    var voiceControlsVisible = false
    var voiceRecognitionDecisionVisible = false
    var voiceEnrollmentVisible = false
    var deviceDecisionVisible = false
    var deviceSelectionVisible = false
    var pairingVisible = false
    var personalizationDecisionVisible = false
    var personalizationScanVisible = false
    var personalizationReviewVisible = false
    var lastHandledFinalVoiceInput = ""
    var acceptsLiveSpeechInput = false
    var currentPromptForSpeechFiltering = ""
    var renderedStep: OnboardingStep?
    var personalizationReviewContentSignature = ""
    var setupInsightQuery = ""
    var collapsedSetupInsightSectionIDs: Set<String> = []
    var permissionRestartPromptVisible = false
    var personalizationScanTaskActive = false

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
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "[" {
            goBackFromUI()
            return
        }

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

    func refreshFromStore() {
        reloadNavigationControls()
        guard renderedStep == store.step else {
            startPrompt()
            return
        }

        switch store.step {
        case .showingPairingQRCode:
            reloadPairingView()
        case .runningPersonalizationScan, .reviewingPersonalizationScan:
            reloadPersonalizationViews()
        case .askingName, .askingAgentName, .renamingAgent, .choosingVoice, .askingVoiceRecognition,
             .enrollingVoice, .settingWakeWord, .askingDeviceSetup, .choosingDevices,
             .askingPersonalizationScan, .askingCredentialInheritance, .complete:
            break
        }
    }

    override func layout() {
        super.layout()
        blurView.frame = bounds

        let reviewingPersonalization = store.step == .reviewingPersonalizationScan
        let contentWidth = min(bounds.width - 152, reviewingPersonalization ? 1080 : 1220)
        let promptHeight = promptHeight(for: contentWidth)
        let inputWidth = min(bounds.width - 152, 680)
        let inputHeight: CGFloat = 68
        let promptY = reviewingPersonalization
            ? max(bounds.height - promptHeight - 112, bounds.height * 0.72)
            : (bounds.height - promptHeight) / 2 + 46

        promptField.frame = NSRect(
            x: (bounds.width - contentWidth) / 2,
            y: promptY,
            width: contentWidth,
            height: promptHeight
        )

        let backButtonSide: CGFloat = 44
        backButton.frame = NSRect(
            x: 28,
            y: bounds.height - backButtonSide - 28,
            width: backButtonSide,
            height: backButtonSide
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

        let personalizationDecisionWidth: CGFloat = 276
        let personalizationDecisionHeight: CGFloat = 70
        personalizationDecisionView.frame = NSRect(
            x: (bounds.width - personalizationDecisionWidth) / 2,
            y: promptY - personalizationDecisionHeight - 42,
            width: personalizationDecisionWidth,
            height: personalizationDecisionHeight
        )
        startPersonalizationButton.frame = NSRect(x: 0, y: 8, width: 126, height: 52)
        skipPersonalizationButton.frame = NSRect(x: 150, y: 8, width: 126, height: 52)

        let personalizationScanWidth = min(bounds.width - 152, 620)
        let personalizationScanHeight: CGFloat = 116
        personalizationScanView.frame = NSRect(
            x: (bounds.width - personalizationScanWidth) / 2,
            y: promptY - personalizationScanHeight - 42,
            width: personalizationScanWidth,
            height: personalizationScanHeight
        )
        personalizationProgressField.frame = NSRect(x: 18, y: 74, width: personalizationScanWidth - 36, height: 22)
        personalizationProgressIndicator.frame = NSRect(x: 22, y: 48, width: personalizationScanWidth - 44, height: 12)
        personalizationTipField.frame = NSRect(x: 18, y: 16, width: personalizationScanWidth - 36, height: 22)

        let personalizationReviewWidth = min(bounds.width - 96, 1120)
        let personalizationReviewBottom: CGFloat = 54
        let personalizationReviewTop = promptField.frame.minY - 34
        let personalizationReviewHeight = max(360, personalizationReviewTop - personalizationReviewBottom)
        personalizationReviewView.frame = NSRect(
            x: (bounds.width - personalizationReviewWidth) / 2,
            y: personalizationReviewBottom,
            width: personalizationReviewWidth,
            height: personalizationReviewHeight
        )
        setupInsightSearchField.frame = NSRect(
            x: 20,
            y: personalizationReviewHeight - 52,
            width: min(360, personalizationReviewWidth - 40),
            height: 32
        )
        personalizationReviewScrollView.frame = NSRect(
            x: 20,
            y: 72,
            width: personalizationReviewWidth - 40,
            height: personalizationReviewHeight - 132
        )
        layoutPersonalizationReviewContent()
        continuePersonalizationButton.frame = NSRect(
            x: (personalizationReviewWidth - 148) / 2,
            y: 14,
            width: 148,
            height: 48
        )
    }
}
