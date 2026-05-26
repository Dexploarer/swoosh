// DetourOnboardingContentViewActions.swift — Detour onboarding view slice (0.5A)

import AppKit
import QuartzCore

extension DetourOnboardingContentView {
    func submit() {
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
        case .askingPersonalizationScan:
            store.askCredentialInheritanceForPersonalization()
        case .askingCredentialInheritance:
            store.setCredentialInheritanceConsent(true)
            runPersonalizationScanFromUI()
            return
        case .runningPersonalizationScan:
            return
        case .reviewingPersonalizationScan:
            if store.setupApplicationReport == nil {
                applyPersonalizationSetupFromUI()
                return
            }
            let advanced = store.continueFromPersonalizationReview()
            reloadPersonalizationViews()
            if !advanced {
                return
            }
        case .complete:
            break
        }

        startPrompt()
    }

    func promptHeight(for width: CGFloat) -> CGFloat {
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
            case "setupInsightSearch":
                setupInsightQuery = field.stringValue
                renderPersonalizationReviewContent()
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
             .askingDeviceSetup, .choosingDevices, .showingPairingQRCode, .askingPersonalizationScan,
             .askingCredentialInheritance, .runningPersonalizationScan, .reviewingPersonalizationScan:
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

    func isCurrentKeyDown(_ keyCodes: UInt16...) -> Bool {
        guard let event = NSApp.currentEvent, event.type == .keyDown else { return false }
        return keyCodes.contains(event.keyCode)
    }

    @objc func voicePopupChanged(_ sender: NSPopUpButton) {
        guard let identifier = sender.selectedItem?.representedObject as? String else { return }
        store.selectVoice(identifier: identifier)
    }

    @objc func previewVoice(_ sender: NSButton) {
        speech.speak(store.voicePreviewText, speech: store.config.speech)
    }

    @objc func selectVoice(_ sender: NSButton) {
        store.confirmVoice()
        startPrompt()
    }

    @objc func keepAgentName(_ sender: NSButton) {
        store.acceptDefaultAgentName()
        startPrompt()
    }

    @objc func renameAgent(_ sender: NSButton) {
        store.startRenamingAgent()
        startPrompt()
    }

    @objc func setupVoiceRecognition(_ sender: NSButton) {
        store.beginVoiceRecognitionSetup()
        voiceRecorder.reset()
        startPrompt()
    }

    @objc func skipVoiceRecognition(_ sender: NSButton) {
        store.skipVoiceEnrollment()
        startPrompt()
    }

    @objc func recordVoiceSample(_ sender: NSButton) {
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

    @objc func skipVoiceEnrollment(_ sender: NSButton) {
        voiceRecorder.reset()
        store.skipVoiceEnrollment()
        startPrompt()
    }

    @objc func continueVoiceEnrollment(_ sender: NSButton) {
        guard voiceRecorder.hasSample else { return }
        store.completeVoiceEnrollment()
        startPrompt()
    }

    @objc func chooseOtherDevices(_ sender: NSButton) {
        store.setWantsOtherAppleDevices(true)
        startPrompt()
    }

    @objc func skipOtherDevices(_ sender: NSButton) {
        store.setWantsOtherAppleDevices(false)
        startPrompt()
    }

    @objc func toggleDevice(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue,
              let device = DetourDeviceKind(rawValue: rawValue) else {
            return
        }

        store.toggleDevice(device)
        reloadDeviceChoices()
    }

    @objc func continueDevices(_ sender: NSButton) {
        guard continueDevicesButton.isEnabled else { return }
        store.continueToPairingQRCode()
        startPrompt()
    }

    @objc func donePairing(_ sender: NSButton) {
        store.finishCurrentDeviceSetup()
        startPrompt()
    }

    @objc func startPersonalization(_ sender: NSButton) {
        switch store.step {
        case .askingPersonalizationScan:
            store.askCredentialInheritanceForPersonalization()
            startPrompt()
        case .askingCredentialInheritance:
            store.setCredentialInheritanceConsent(true)
            runPersonalizationScanFromUI()
        default:
            runPersonalizationScanFromUI()
        }
    }

    @objc func skipPersonalization(_ sender: NSButton) {
        if store.step == .askingCredentialInheritance {
            store.setCredentialInheritanceConsent(false)
            runPersonalizationScanFromUI()
        } else {
            store.skipPersonalizationScan()
            startPrompt()
        }
    }

    @objc func continuePersonalization(_ sender: NSButton) {
        guard continuePersonalizationButton.isEnabled else { return }
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

    func applyPersonalizationSetupFromUI() {
        guard !store.isApplyingSetup else { return }
        reloadPersonalizationViews()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let advanced = await store.applySetupFromPersonalizationReview { [weak self] _ in
                self?.reloadPersonalizationViews()
            }
            reloadPersonalizationViews()
            if advanced {
                startPrompt()
            }
        }
    }

    @objc func goBack(_ sender: NSButton) {
        goBackFromUI()
    }

    func showPermissionRestartPrompt() {
        guard !permissionRestartPromptVisible else { return }
        permissionRestartPromptVisible = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self else { return }
            defer { self.permissionRestartPromptVisible = false }
            let alert = NSAlert()
            alert.messageText = "Restart Detour after granting access"
            alert.informativeText = "Detour saved this setup step. Enable Detour in Full Disk Access, then restart to come back here with the new permission."
            alert.addButton(withTitle: "Restart Detour")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                self.restartDetourPreservingOnboarding()
            }
        }
    }

    func restartDetourPreservingOnboarding() {
        store.prepareForPermissionRestart()
        let bundlePath = Bundle.main.bundleURL.path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "sleep 0.35; /usr/bin/open -n \(shellSingleQuoted(bundlePath))"
        ]
        try? process.run()
        NSApp.terminate(nil)
    }

    func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
