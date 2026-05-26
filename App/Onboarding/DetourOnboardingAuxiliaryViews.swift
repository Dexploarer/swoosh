// DetourOnboardingAuxiliaryViews.swift — Detour onboarding view slice (0.5A)

import AppKit

final class DetourFlippedView: NSView {
    override var isFlipped: Bool { true }
}

extension Array where Element == DetourSetupCandidate {
    func sortedForReview() -> [DetourSetupCandidate] {
        sorted { lhs, rhs in
            if lhs.recommended != rhs.recommended {
                return lhs.recommended
            }
            if lhs.category.rawValue != rhs.category.rawValue {
                return lhs.category.rawValue < rhs.category.rawValue
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}

final class DetourDeviceOptionButton: NSButton {
    let iconView = NSImageView()
    let titleField = NSTextField(labelWithString: "")
    let checkmarkView = NSImageView()

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

final class DetourInputField: NSTextField {
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
}
