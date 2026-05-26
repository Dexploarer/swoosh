// DetourPersonalizationCandidateRowView.swift — Detour onboarding view slice (0.5A)

import AppKit
import QuartzCore

struct DetourPersonalizationCandidateGroup {
    var title: String
    var detail: String?
    var candidates: [DetourSetupCandidate]
}

final class DetourPersonalizationCandidateRowView: NSView {
    var onApprovalChanged: ((String, Bool) -> Void)?
    var onScopeChanged: ((String, DetourDelegationRole) -> Void)?
    var onPermissionRequested: ((String) -> Void)?

    let candidate: DetourSetupCandidate
    var approved: Bool
    var scope: DetourDelegationRole?
    let userName: String
    let agentName: String
    let titleField = NSTextField(labelWithString: "")
    let detailField = NSTextField(labelWithString: "")
    let statusField = NSTextField(labelWithString: "")
    let applyButton = NSButton(title: "Use", target: nil, action: nil)
    let skipButton = NSButton(title: "Remove", target: nil, action: nil)
    let permissionButton = NSButton(title: "Grant Access", target: nil, action: nil)
    let userButton = NSButton(title: "As me", target: nil, action: nil)
    let agentButton = NSButton(title: "As agent", target: nil, action: nil)

    override var isFlipped: Bool { true }

    init(
        candidate: DetourSetupCandidate,
        approved: Bool,
        scope: DetourDelegationRole?,
        userName: String,
        agentName: String
    ) {
        self.candidate = candidate
        self.approved = approved
        self.scope = scope
        self.userName = userName
        self.agentName = agentName
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1

        titleField.stringValue = rowTitle(candidate)
        titleField.font = .systemFont(ofSize: 13, weight: .semibold)
        titleField.textColor = .white
        titleField.lineBreakMode = .byTruncatingMiddle
        addSubview(titleField)

        detailField.stringValue = rowDetail(candidate)
        detailField.font = .systemFont(ofSize: 12, weight: .medium)
        detailField.textColor = NSColor.white.withAlphaComponent(0.68)
        detailField.lineBreakMode = .byTruncatingTail
        addSubview(detailField)

        statusField.font = .systemFont(ofSize: 11, weight: .bold)
        statusField.alignment = .center
        statusField.textColor = .white
        statusField.wantsLayer = true
        statusField.layer?.cornerRadius = 7
        statusField.layer?.masksToBounds = true
        addSubview(statusField)

        permissionButton.title = setupActionTitle
        configureButton(applyButton, action: #selector(apply(_:)))
        configureButton(skipButton, action: #selector(skip(_:)))
        configureButton(permissionButton, action: #selector(grantPermission(_:)))
        configureButton(userButton, action: #selector(scopeUser(_:)))
        configureButton(agentButton, action: #selector(scopeAgent(_:)))
        addSubview(applyButton)
        addSubview(skipButton)
        addSubview(permissionButton)
        addSubview(userButton)
        addSubview(agentButton)
        updateVisualState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let buttonWidth: CGFloat = 78
        let scopeWidth: CGFloat = 86
        let permissionWidth: CGFloat = 118
        let gap: CGFloat = 8
        let showsScope = supportsScopeControls
        let showsPermission = supportsPermissionButton
        let controlsWidth = (buttonWidth * 2)
            + (showsScope ? (scopeWidth * 2) : 0)
            + (showsPermission ? permissionWidth : 0)
            + CGFloat((showsScope ? 2 : 0) + (showsPermission ? 1 : 0) + 1) * gap
        let controlsX = max(12, bounds.width - controlsWidth - 12)
        titleField.frame = NSRect(x: 14, y: 10, width: max(160, controlsX - 28), height: 20)
        detailField.frame = NSRect(x: 14, y: 34, width: max(160, controlsX - 28), height: 18)
        statusField.frame = NSRect(x: 14, y: 58, width: max(148, min(260, controlsX - 28)), height: 18)
        userButton.isHidden = !showsScope
        agentButton.isHidden = !showsScope
        permissionButton.isHidden = !showsPermission
        var controlX = controlsX
        if showsScope {
            userButton.frame = NSRect(x: controlX, y: 24, width: scopeWidth, height: 34)
            controlX = userButton.frame.maxX + gap
            agentButton.frame = NSRect(x: controlX, y: 24, width: scopeWidth, height: 34)
            controlX = agentButton.frame.maxX + gap
        }
        if showsPermission {
            permissionButton.frame = NSRect(x: controlX, y: 24, width: permissionWidth, height: 34)
            controlX = permissionButton.frame.maxX + gap
        }
        applyButton.frame = NSRect(x: controlX, y: 24, width: buttonWidth, height: 34)
        skipButton.frame = NSRect(x: applyButton.frame.maxX + gap, y: 24, width: buttonWidth, height: 34)
    }
}
