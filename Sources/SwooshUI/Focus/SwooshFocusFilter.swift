// SwooshUI/Focus/SwooshFocusFilter.swift — Focus-mode preset switcher (0.4A)
//
// When the user enters a macOS / iOS Focus mode, Swoosh can swap its
// MenuBar + Toolbar presets accordingly. The intent registers as a Focus
// Filter (Settings → Focus → <Mode> → Filters) so Apple's UI surfaces it
// natively — no custom settings sheet needed.

import Foundation
#if canImport(AppIntents)
import AppIntents
#endif

// MARK: - Filter state

/// The combined preset state Swoosh applies when a Focus mode is active.
public struct SwooshFocusPreset: Codable, Sendable, Equatable {
    public var menuBarPresetID: String?
    public var toolbarPresetID: String?
    public var disableNotifications: Bool
    public var hideUsageMeters: Bool

    public init(
        menuBarPresetID: String? = nil,
        toolbarPresetID: String? = nil,
        disableNotifications: Bool = false,
        hideUsageMeters: Bool = false
    ) {
        self.menuBarPresetID = menuBarPresetID
        self.toolbarPresetID = toolbarPresetID
        self.disableNotifications = disableNotifications
        self.hideUsageMeters = hideUsageMeters
    }
}

// MARK: - Notifications

public extension Notification.Name {
    /// Fired when a Focus filter wants to apply a preset bundle. The
    /// notification's `object` carries a `SwooshFocusPreset` value.
    static let swooshApplyFocusPreset = Notification.Name("ai.swoosh.applyFocusPreset")
}

// MARK: - App Intent

#if canImport(AppIntents)
@available(macOS 13.0, iOS 16.0, *)
public struct SwooshSetFocusPresetIntent: SetFocusFilterIntent {
    public static let title: LocalizedStringResource = "Switch Swoosh Preset"
    public static let description = IntentDescription(
        "Apply Swoosh menu bar + toolbar presets when this Focus is active."
    )

    @Parameter(title: "Menu Bar Preset")
    public var menuBar: MenuBarPresetChoice?

    @Parameter(title: "Toolbar Preset")
    public var toolbar: ToolbarPresetChoice?

    @Parameter(title: "Mute notifications")
    public var muteNotifications: Bool?

    @Parameter(title: "Hide usage meters")
    public var hideUsageMeters: Bool?

    public init() {
        self.muteNotifications = nil
        self.hideUsageMeters = nil
    }

    public var displayRepresentation: DisplayRepresentation {
        var parts: [String] = []
        if let m = menuBar?.rawValue   { parts.append("menu bar = \(m)") }
        if let t = toolbar?.rawValue   { parts.append("toolbar = \(t)") }
        if muteNotifications == true   { parts.append("muted") }
        if hideUsageMeters == true     { parts.append("meters hidden") }
        let subtitle = parts.isEmpty ? "no overrides" : parts.joined(separator: ", ")
        return DisplayRepresentation(
            title: "Swoosh Focus Preset",
            subtitle: "\(subtitle)"
        )
    }

    public func perform() async throws -> some IntentResult {
        let preset = SwooshFocusPreset(
            menuBarPresetID: menuBar?.rawValue,
            toolbarPresetID: toolbar?.rawValue,
            disableNotifications: muteNotifications == true,
            hideUsageMeters: hideUsageMeters == true
        )
        await MainActor.run {
            NotificationCenter.default.post(
                name: .swooshApplyFocusPreset,
                object: preset
            )
        }
        return .result()
    }
}

// MARK: - Parameter choices

@available(macOS 13.0, iOS 16.0, *)
public enum MenuBarPresetChoice: String, AppEnum {
    case swoosh, codexBar, minimal, developer, monitor, agent

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Menu Bar Preset")
    public static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .swoosh:    "Detour",
        .codexBar:  "CodexBar",
        .minimal:   "Minimal",
        .developer: "Developer",
        .monitor:   "Monitor",
        .agent:     "Agent",
    ]
}

@available(macOS 13.0, iOS 16.0, *)
public enum ToolbarPresetChoice: String, AppEnum {
    case `default`, developer, trader, minimal, focus

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Toolbar Preset")
    public static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .default:   "Default",
        .developer: "Developer",
        .trader:    "Trader",
        .minimal:   "Minimal",
        .focus:     "Focus",
    ]
}
#endif
