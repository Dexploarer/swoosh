// DetourOnboardingContentViewLayout.swift — Detour onboarding view slice (0.5A)

import AppKit
import QuartzCore

extension DetourOnboardingContentView {
    func layoutPersonalizationReviewContent() {
        renderPersonalizationReviewContent()
    }

    func layoutDeviceButtons(width: CGFloat) {
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

    func deviceSelectionHeight() -> CGFloat {
        let columns = 4
        let rows = max(1, Int(ceil(Double(store.availableDeviceKinds.count) / Double(columns))))
        let tileArea = CGFloat(rows) * 72 + CGFloat(max(0, rows - 1)) * 12
        let remoteFieldsHeight: CGFloat = store.selectedDeviceKinds.contains(.remoteDetour) ? 112 : 0
        return 18 + tileArea + remoteFieldsHeight + 76
    }

    func layoutRemoteFields(width: CGFloat) {
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

    func reloadVoiceChoices() {
        voicePopup.removeAllItems()
        voicePopup.addItem(withTitle: "OmniVoice local")
        voicePopup.lastItem?.representedObject = DetourVoiceIdentifier.omniVoiceLocal
        voicePopup.selectItem(at: 0)
    }

    func reloadVoiceEnrollmentControls() {
        voiceEnrollmentStatusField.stringValue = voiceRecorder.statusText
        recordVoiceButton.title = voiceRecorder.isRecording ? "Stop" : "Record"
        continueVoiceEnrollmentButton.isEnabled = voiceRecorder.hasSample
        continueVoiceEnrollmentButton.alphaValue = voiceRecorder.hasSample ? 1 : 0.44
    }

    func reloadDeviceChoices() {
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

    func reloadPairingView() {
        if store.pairingInfo == nil && store.pairingError == nil {
            store.continueToPairingQRCode()
        }

        qrImageView.image = store.pairingInfo?.qrImage
        if let name = store.pairedDeviceName {
            pairingDetailField.stringValue = "\(name) connected"
        } else if let pairingInfo = store.pairingInfo {
            pairingDetailField.stringValue = "Waiting on \(pairingInfo.host) - code \(pairingInfo.confirmationCode)"
        } else {
            pairingDetailField.stringValue = store.pairingError ?? "Pairing unavailable"
        }
    }

    func reloadPersonalizationViews() {
        personalizationProgressIndicator.doubleValue = store.personalizationProgress.fraction
        personalizationProgressField.stringValue = store.personalizationProgress.title
        personalizationTipField.stringValue = store.personalizationProgress.tip
        renderPersonalizationReviewContent()
        continuePersonalizationButton.isEnabled = store.personalizationReviewHasContent && !store.isApplyingSetup
        continuePersonalizationButton.title = store.isApplyingSetup
            ? "Applying..."
            : store.setupApplicationReport == nil ? "Apply setup" : "Continue"
        continuePersonalizationButton.alphaValue = continuePersonalizationButton.isEnabled ? 1 : 0.44
    }

}
