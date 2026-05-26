// DetourSetupInsightItemRow.swift — setup insight review row (0.5A)

import AppKit

final class DetourSetupInsightItemRow: NSView {
    var onAction: ((DetourSetupInsightAction) -> Void)?

    private let item: DetourSetupInsightItem
    private let titleField = NSTextField(labelWithString: "")
    private let detailField = NSTextField(labelWithString: "")
    private let statusField = NSTextField(labelWithString: "")
    private var actionButtons: [NSButton] = []
    private var actionsByID: [String: DetourSetupInsightAction] = [:]

    override var isFlipped: Bool { true }

    init(item: DetourSetupInsightItem) {
        self.item = item
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.backgroundColor = rowBackground.cgColor
        layer?.borderColor = rowBorder.cgColor
        configureLabels()
        configureButtons()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let padding: CGFloat = 14
        let buttonWidth: CGFloat = 110
        let buttonHeight: CGFloat = 32
        let gap: CGFloat = 8
        let visibleButtons = actionButtons.filter { !$0.isHidden }
        let controlsWidth = CGFloat(visibleButtons.count) * buttonWidth
            + CGFloat(max(0, visibleButtons.count - 1)) * gap
        let controlsX = max(padding, bounds.width - padding - controlsWidth)
        titleField.frame = NSRect(x: padding, y: 10, width: max(180, controlsX - padding * 2), height: 20)
        detailField.frame = NSRect(x: padding, y: 34, width: max(180, controlsX - padding * 2), height: 34)
        statusField.frame = NSRect(x: padding, y: 70, width: 190, height: 20)
        var x = controlsX
        for button in visibleButtons {
            button.frame = NSRect(x: x, y: 30, width: buttonWidth, height: buttonHeight)
            x += buttonWidth + gap
        }
    }

    private func configureLabels() {
        titleField.stringValue = item.title
        titleField.font = .systemFont(ofSize: 13, weight: .semibold)
        titleField.textColor = .white
        titleField.lineBreakMode = .byTruncatingTail
        addSubview(titleField)

        detailField.stringValue = item.detail
        detailField.font = .systemFont(ofSize: 12, weight: .medium)
        detailField.textColor = NSColor.white.withAlphaComponent(0.68)
        detailField.maximumNumberOfLines = 2
        detailField.lineBreakMode = .byWordWrapping
        detailField.cell?.wraps = true
        addSubview(detailField)

        statusField.stringValue = statusLabel
        statusField.font = .systemFont(ofSize: 11, weight: .bold)
        statusField.alignment = .center
        statusField.textColor = .white
        statusField.wantsLayer = true
        statusField.layer?.cornerRadius = 7
        statusField.layer?.masksToBounds = true
        statusField.layer?.backgroundColor = statusColor.cgColor
        addSubview(statusField)
    }

    private func configureButtons() {
        actionButtons = item.actions.prefix(4).map { action in
            let actionID = DetourSetupInsightRedaction.stableID(
                prefix: "action",
                components: [action.kind.rawValue, action.targetID]
            )
            let button = NSButton(title: action.title, target: self, action: #selector(runAction(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(actionID)
            actionsByID[actionID] = action
            button.isBordered = false
            button.font = .systemFont(ofSize: 12, weight: .semibold)
            button.contentTintColor = .white
            button.refusesFirstResponder = true
            button.focusRingType = .default
            button.wantsLayer = true
            button.layer?.cornerRadius = 8
            button.layer?.backgroundColor = buttonColor(for: action.kind).cgColor
            button.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
            button.layer?.borderWidth = 1
            addSubview(button)
            return button
        }
    }

    @objc private func runAction(_ sender: NSButton) {
        guard let actionID = sender.identifier?.rawValue,
              let action = actionsByID[actionID] else { return }
        onAction?(action)
    }

    private var statusLabel: String {
        switch item.status {
        case .selected:
            return "Selected"
        case .using:
            return "Using"
        case .removed:
            return "Not using"
        case .pending:
            return "Pending"
        case .verified:
            return "Verified"
        case .failed:
            return "Failed"
        case .blocked:
            return "Blocked"
        case .needsPermission:
            return "Needs permission"
        case .needsConfiguration:
            return "Needs configuration"
        case .unknown:
            return "Unknown"
        }
    }

    private var rowBackground: NSColor {
        switch item.status {
        case .verified, .using:
            return NSColor.systemGreen.withAlphaComponent(0.12)
        case .selected:
            return NSColor.systemBlue.withAlphaComponent(0.12)
        case .failed, .blocked:
            return NSColor.systemRed.withAlphaComponent(0.12)
        case .needsPermission, .needsConfiguration:
            return NSColor.systemYellow.withAlphaComponent(0.12)
        case .removed:
            return NSColor.black.withAlphaComponent(0.12)
        case .pending:
            return NSColor.white.withAlphaComponent(0.08)
        case .unknown:
            return NSColor.white.withAlphaComponent(0.06)
        }
    }

    private var rowBorder: NSColor {
        switch item.status {
        case .verified, .using:
            return NSColor.systemGreen.withAlphaComponent(0.42)
        case .selected:
            return NSColor.systemBlue.withAlphaComponent(0.38)
        case .failed, .blocked:
            return NSColor.systemRed.withAlphaComponent(0.42)
        case .needsPermission, .needsConfiguration:
            return NSColor.systemYellow.withAlphaComponent(0.42)
        case .removed:
            return NSColor.white.withAlphaComponent(0.14)
        case .pending:
            return NSColor.white.withAlphaComponent(0.2)
        case .unknown:
            return NSColor.white.withAlphaComponent(0.14)
        }
    }

    private var statusColor: NSColor {
        switch item.status {
        case .verified, .using:
            return NSColor.systemGreen.withAlphaComponent(0.46)
        case .selected:
            return NSColor.systemBlue.withAlphaComponent(0.42)
        case .failed, .blocked:
            return NSColor.systemRed.withAlphaComponent(0.48)
        case .needsPermission, .needsConfiguration:
            return NSColor.systemYellow.withAlphaComponent(0.44)
        case .removed:
            return NSColor.white.withAlphaComponent(0.16)
        case .pending:
            return NSColor.systemBlue.withAlphaComponent(0.36)
        case .unknown:
            return NSColor.white.withAlphaComponent(0.2)
        }
    }

    private func buttonColor(for kind: DetourSetupInsightActionKind) -> NSColor {
        switch kind {
        case .remove:
            return NSColor.white.withAlphaComponent(0.14)
        case .grantPermission, .configure, .openDoctor:
            return NSColor.systemYellow.withAlphaComponent(0.36)
        case .scopeUser:
            return NSColor.systemOrange.withAlphaComponent(0.4)
        case .scopeAgent, .openRelationshipQA:
            return NSColor.systemBlue.withAlphaComponent(0.4)
        case .use:
            return NSColor.systemGreen.withAlphaComponent(0.42)
        }
    }
}
