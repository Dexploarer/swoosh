// SwooshUI/Interactions/EditMenu.swift — Native Edit menu commands (0.4A)
//
// Provides a `Commands` group that adds Swoosh-specific items to the
// system Edit menu and a chat-aware Commands set surfaced under a custom
// "Swoosh" top-level menu. Wire via `.commands { SwooshEditCommands() }`
// inside a `Scene`.

import SwiftUI

public struct SwooshEditCommands: Commands {
    public init() {}

    public var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Pin to Memory") {
                NotificationCenter.default.post(name: .swooshPinSelection, object: nil)
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Send to Chat") {
                NotificationCenter.default.post(name: .swooshSendToChat, object: nil)
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
        }

        CommandMenu("Detour") {
            Button("New Chat") {
                NotificationCenter.default.post(name: .swooshNewChat, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button("Run Last Workflow") {
                NotificationCenter.default.post(name: .swooshRunLastWorkflow, object: nil)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Button("Review Approvals…") {
                NotificationCenter.default.post(name: .swooshOpenApprovals, object: nil)
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])

            Button("Show Audit Log") {
                NotificationCenter.default.post(name: .swooshOpenAuditLog, object: nil)
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])

            Divider()

            Button("Customize Appearance…") {
                NotificationCenter.default.post(name: .swooshOpenAppearance, object: nil)
            }
            .keyboardShortcut(",", modifiers: [.command, .shift])
        }
    }
}

// MARK: - Notification names

public extension Notification.Name {
    static let swooshPinSelection      = Notification.Name("ai.swoosh.pinSelection")
    static let swooshSendToChat        = Notification.Name("ai.swoosh.sendToChat")
    static let swooshNewChat           = Notification.Name("ai.swoosh.newChat")
    static let swooshRunLastWorkflow   = Notification.Name("ai.swoosh.runLastWorkflow")
    static let swooshOpenApprovals     = Notification.Name("ai.swoosh.openApprovals")
    static let swooshOpenAuditLog      = Notification.Name("ai.swoosh.openAuditLog")
    static let swooshOpenAppearance    = Notification.Name("ai.swoosh.openAppearance")
}
