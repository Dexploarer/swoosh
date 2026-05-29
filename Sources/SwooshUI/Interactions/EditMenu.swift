#if os(macOS)

// SwooshUI/Interactions/EditMenu.swift — Context-aware menu bar commands
//
// The Detour menu adapts its items based on which dashboard tab is
// currently focused. Each tab gets a rich set of power-user commands
// with keyboard shortcuts, inspired by Cursor, Linear, Arc, and Raycast.
//
// Menu structure:
//   Edit        — standard + Pin to Memory, Send to Chat
//   View        — sidebar, full screen, tab navigation
//   Detour      — context-aware: changes per active tab

import SwiftUI

// ═══════════════════════════════════════════════════════════════════
// MARK: - Edit menu additions
// ═══════════════════════════════════════════════════════════════════

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

        // ── View menu ──────────────────────────────────────
        CommandGroup(after: .toolbar) {
            Divider()

            Button("Toggle Sidebar") {
                NotificationCenter.default.post(name: .swooshToggleSidebar, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .control])

            Divider()

            // Quick tab navigation
            Button("Go to Chat") {
                NotificationCenter.default.post(name: .swooshNavigateTab, object: "chat")
            }
            .keyboardShortcut("1", modifiers: [.command])

            Button("Go to Memories") {
                NotificationCenter.default.post(name: .swooshNavigateTab, object: "memories")
            }
            .keyboardShortcut("2", modifiers: [.command])

            Button("Go to Skills") {
                NotificationCenter.default.post(name: .swooshNavigateTab, object: "skills")
            }
            .keyboardShortcut("3", modifiers: [.command])

            Button("Go to Providers") {
                NotificationCenter.default.post(name: .swooshNavigateTab, object: "providers")
            }
            .keyboardShortcut("4", modifiers: [.command])

            Button("Go to Tools") {
                NotificationCenter.default.post(name: .swooshNavigateTab, object: "tools")
            }
            .keyboardShortcut("5", modifiers: [.command])

            Button("Go to Audit Log") {
                NotificationCenter.default.post(name: .swooshNavigateTab, object: "audit")
            }
            .keyboardShortcut("6", modifiers: [.command])

            Button("Go to Voice Mode") {
                NotificationCenter.default.post(name: .swooshNavigateTab, object: "voice")
            }
            .keyboardShortcut("7", modifiers: [.command])

            Button("Go to Settings") {
                NotificationCenter.default.post(name: .swooshNavigateTab, object: "settings")
            }
            .keyboardShortcut(",", modifiers: [.command])
        }

        // ── Detour menu (context-aware) ────────────────────
        CommandMenu("Detour") {
            DetourMenuContent()
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Detour menu (adapts to active tab)
// ═══════════════════════════════════════════════════════════════════

private struct DetourMenuContent: View {
    @FocusedValue(\.activeDashboardTab) var activeTab

    var body: some View {
        // ── Always-present items ──
        Group {
            Button("New Chat") {
                NotificationCenter.default.post(name: .swooshNewChat, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button("Command Palette…") {
                NotificationCenter.default.post(name: .swooshCommandPalette, object: nil)
            }
            .keyboardShortcut("k", modifiers: [.command])
        }

        Divider()

        // ── Context-specific items ──
        switch activeTab {
        case .chat, .gaming, nil:
            chatMenuItems
        case .memories:
            memoriesMenuItems
        case .skills:
            skillsMenuItems
        case .wallet, .launchpads:
            walletMenuItems
        case .models:
            providersMenuItems
        case .tools:
            toolsMenuItems
        case .audit:
            auditMenuItems
        case .voice:
            voiceMenuItems
        case .safety, .settings:
            settingsMenuItems
        }

        Divider()

        // ── Always-present footer ──
        Group {
            Button("Review Approvals…") {
                NotificationCenter.default.post(name: .swooshOpenApprovals, object: nil)
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])

            Button("Quick Search…") {
                NotificationCenter.default.post(name: .swooshQuickSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button("Why? — Explain Last Response") {
                NotificationCenter.default.post(name: .swooshExplainWhy, object: nil)
            }
            .keyboardShortcut("/", modifiers: [.command])
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Chat
    // ─────────────────────────────────────────────────────────────────

    @ViewBuilder
    private var chatMenuItems: some View {
        Button("Regenerate Last Reply") {
            NotificationCenter.default.post(name: .swooshRegenerateReply, object: nil)
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])

        Button("Fork Conversation") {
            NotificationCenter.default.post(name: .swooshForkChat, object: nil)
        }

        Button("Clear Conversation") {
            NotificationCenter.default.post(name: .swooshClearChat, object: nil)
        }

        Divider()

        Button("Export as Markdown…") {
            NotificationCenter.default.post(name: .swooshExportMarkdown, object: nil)
        }
        .keyboardShortcut("e", modifiers: [.command, .shift])

        Button("Export as JSON…") {
            NotificationCenter.default.post(name: .swooshExportJSON, object: nil)
        }

        Divider()

        Button("Attach File…") {
            NotificationCenter.default.post(name: .swooshAttachFile, object: nil)
        }
        .keyboardShortcut("o", modifiers: [.command, .shift])

        Button("Attach Screenshot") {
            NotificationCenter.default.post(name: .swooshAttachScreenshot, object: nil)
        }
        .keyboardShortcut("s", modifiers: [.command, .shift])

        Button("Attach Clipboard") {
            NotificationCenter.default.post(name: .swooshAttachClipboard, object: nil)
        }

        Divider()

        Button("Insert /command…") {
            NotificationCenter.default.post(name: .swooshInsertSlashCommand, object: nil)
        }

        Button("Run Last Workflow") {
            NotificationCenter.default.post(name: .swooshRunLastWorkflow, object: nil)
        }
        .keyboardShortcut("r", modifiers: [.command, .control])

        Button("Run Workflow…") {
            NotificationCenter.default.post(name: .swooshRunWorkflow, object: nil)
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Memories
    // ─────────────────────────────────────────────────────────────────

    @ViewBuilder
    private var memoriesMenuItems: some View {
        Button("Add Memory…") {
            NotificationCenter.default.post(name: .swooshAddMemory, object: nil)
        }
        .keyboardShortcut("m", modifiers: [.command, .shift])

        Button("Search Memories…") {
            NotificationCenter.default.post(name: .swooshSearchMemories, object: nil)
        }

        Divider()

        Button("Review Pending Candidates") {
            NotificationCenter.default.post(name: .swooshReviewCandidates, object: nil)
        }

        Button("Approve All Candidates") {
            NotificationCenter.default.post(name: .swooshApproveAll, object: nil)
        }

        Button("Reject All Candidates") {
            NotificationCenter.default.post(name: .swooshRejectAll, object: nil)
        }

        Divider()

        Button("Run Scout Scan Now") {
            NotificationCenter.default.post(name: .swooshRunScout, object: nil)
        }

        Button("Export Memories…") {
            NotificationCenter.default.post(name: .swooshExportMemories, object: nil)
        }

        Button("Import Memories…") {
            NotificationCenter.default.post(name: .swooshImportMemories, object: nil)
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Skills
    // ─────────────────────────────────────────────────────────────────

    @ViewBuilder
    private var skillsMenuItems: some View {
        Button("Create Skill…") {
            NotificationCenter.default.post(name: .swooshCreateSkill, object: nil)
        }

        Button("Import Skill from File…") {
            NotificationCenter.default.post(name: .swooshImportSkill, object: nil)
        }

        Divider()

        Button("Promote Selected to Reviewed") {
            NotificationCenter.default.post(name: .swooshPromoteSkill, object: nil)
        }

        Button("Freeze Selected") {
            NotificationCenter.default.post(name: .swooshFreezeSkill, object: nil)
        }

        Divider()

        Button("Reload Bundled Skills") {
            NotificationCenter.default.post(name: .swooshReloadBundledSkills, object: nil)
        }

        Button("Export All Skills…") {
            NotificationCenter.default.post(name: .swooshExportSkills, object: nil)
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Wallet / Web3
    // ─────────────────────────────────────────────────────────────────

    @ViewBuilder
    private var walletMenuItems: some View {
        Button("Refresh Portfolio") {
            NotificationCenter.default.post(name: .swooshRefreshWallet, object: nil)
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])

        Button("Create Wallet…") {
            NotificationCenter.default.post(name: .swooshCreateWallet, object: nil)
        }

        Button("Import Wallet…") {
            NotificationCenter.default.post(name: .swooshImportWallet, object: nil)
        }

        Divider()

        Button("View on Explorer") {
            NotificationCenter.default.post(name: .swooshViewExplorer, object: nil)
        }

        Button("Copy Address") {
            NotificationCenter.default.post(name: .swooshCopyAddress, object: nil)
        }
        .keyboardShortcut("c", modifiers: [.command, .shift])
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Providers
    // ─────────────────────────────────────────────────────────────────

    @ViewBuilder
    private var providersMenuItems: some View {
        Button("Add Provider…") {
            NotificationCenter.default.post(name: .swooshAddProvider, object: nil)
        }

        Button("Configure API Keys…") {
            NotificationCenter.default.post(name: .swooshConfigureKeys, object: nil)
        }
        .keyboardShortcut("k", modifiers: [.command, .option])

        Divider()

        Button("Test Connection") {
            NotificationCenter.default.post(name: .swooshTestProvider, object: nil)
        }
        .keyboardShortcut("t", modifiers: [.command, .shift])

        Button("Refresh Model List") {
            NotificationCenter.default.post(name: .swooshRefreshModels, object: nil)
        }

        Divider()

        Button("Switch to Local MLX") {
            NotificationCenter.default.post(name: .swooshSwitchToMLX, object: nil)
        }

        Button("Switch to Apple Foundation") {
            NotificationCenter.default.post(name: .swooshSwitchToFoundation, object: nil)
        }

        Button("Download Model…") {
            NotificationCenter.default.post(name: .swooshDownloadModel, object: nil)
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Tools
    // ─────────────────────────────────────────────────────────────────

    @ViewBuilder
    private var toolsMenuItems: some View {
        Button("Grant Permission…") {
            NotificationCenter.default.post(name: .swooshGrantPermission, object: nil)
        }
        .keyboardShortcut("g", modifiers: [.command, .shift])

        Button("Revoke All Permissions") {
            NotificationCenter.default.post(name: .swooshRevokeAllPermissions, object: nil)
        }

        Divider()

        Button("Register MCP Server…") {
            NotificationCenter.default.post(name: .swooshRegisterMCP, object: nil)
        }

        Button("Connect MCP Server") {
            NotificationCenter.default.post(name: .swooshConnectMCP, object: nil)
        }

        Button("Disconnect MCP Server") {
            NotificationCenter.default.post(name: .swooshDisconnectMCP, object: nil)
        }

        Divider()

        Button("Filter by Toolset…") {
            NotificationCenter.default.post(name: .swooshFilterToolset, object: nil)
        }

        Button("Show Crypto Toolsets") {
            NotificationCenter.default.post(name: .swooshShowCryptoTools, object: nil)
        }

        Button("Show DeFi Toolsets") {
            NotificationCenter.default.post(name: .swooshShowDeFiTools, object: nil)
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Audit
    // ─────────────────────────────────────────────────────────────────

    @ViewBuilder
    private var auditMenuItems: some View {
        Button("Show Audit Log") {
            NotificationCenter.default.post(name: .swooshOpenAuditLog, object: nil)
        }
        .keyboardShortcut("l", modifiers: [.command, .shift])

        Button("Search Audit Entries…") {
            NotificationCenter.default.post(name: .swooshSearchAudit, object: nil)
        }

        Divider()

        Button("Filter: Tool Calls Only") {
            NotificationCenter.default.post(name: .swooshAuditFilterTool, object: nil)
        }

        Button("Filter: Permissions Only") {
            NotificationCenter.default.post(name: .swooshAuditFilterPerm, object: nil)
        }

        Button("Filter: Crypto Tx Only") {
            NotificationCenter.default.post(name: .swooshAuditFilterCrypto, object: nil)
        }

        Button("Clear Filters") {
            NotificationCenter.default.post(name: .swooshAuditClearFilters, object: nil)
        }

        Divider()

        Button("Export Audit Log…") {
            NotificationCenter.default.post(name: .swooshExportAudit, object: nil)
        }

        Button("Verify Merkle Anchors") {
            NotificationCenter.default.post(name: .swooshVerifyAnchors, object: nil)
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Voice
    // ─────────────────────────────────────────────────────────────────

    @ViewBuilder
    private var voiceMenuItems: some View {
        Button("Start / Stop Voice Mode") {
            NotificationCenter.default.post(name: .swooshToggleVoiceNotif, object: nil)
        }
        .keyboardShortcut(.space, modifiers: [.option, .shift])

        Divider()

        Button("Switch Orb Theme…") {
            NotificationCenter.default.post(name: .swooshSwitchOrbTheme, object: nil)
        }

        Button("Next Orb Theme") {
            NotificationCenter.default.post(name: .swooshNextOrbTheme, object: nil)
        }
        .keyboardShortcut("]", modifiers: [.command])

        Button("Previous Orb Theme") {
            NotificationCenter.default.post(name: .swooshPrevOrbTheme, object: nil)
        }
        .keyboardShortcut("[", modifiers: [.command])

        Divider()

        Button("Toggle Push to Talk") {
            NotificationCenter.default.post(name: .swooshTogglePTT, object: nil)
        }

        Button("Toggle Speak Replies") {
            NotificationCenter.default.post(name: .swooshToggleTTS, object: nil)
        }

        Divider()

        Button("Switch STT Engine…") {
            NotificationCenter.default.post(name: .swooshSwitchSTT, object: nil)
        }

        Button("Switch TTS Engine…") {
            NotificationCenter.default.post(name: .swooshSwitchTTS, object: nil)
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Settings
    // ─────────────────────────────────────────────────────────────────

    @ViewBuilder
    private var settingsMenuItems: some View {
        Button("Customize Appearance…") {
            NotificationCenter.default.post(name: .swooshOpenAppearance, object: nil)
        }
        .keyboardShortcut(",", modifiers: [.command, .shift])

        Button("Change Theme") {
            NotificationCenter.default.post(name: .swooshChangeTheme, object: nil)
        }

        Divider()

        Button("Configure Daemon") {
            NotificationCenter.default.post(name: .swooshConfigureDaemon, object: nil)
        }

        Button("Restart Daemon") {
            NotificationCenter.default.post(name: .swooshRestartDaemon, object: nil)
        }

        Divider()

        Button("Scout Personalisation Depth…") {
            NotificationCenter.default.post(name: .swooshScoutDepth, object: nil)
        }

        Button("Manage Keychain Secrets…") {
            NotificationCenter.default.post(name: .swooshManageSecrets, object: nil)
        }

        Button("Reset All Settings") {
            NotificationCenter.default.post(name: .swooshResetSettings, object: nil)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Notification names
// ═══════════════════════════════════════════════════════════════════

public extension Notification.Name {
    // Edit
    static let swooshPinSelection       = Notification.Name("ai.swoosh.pinSelection")
    static let swooshSendToChat         = Notification.Name("ai.swoosh.sendToChat")

    // View
    static let swooshToggleSidebar      = Notification.Name("ai.swoosh.toggleSidebar")
    static let swooshNavigateTab        = Notification.Name("ai.swoosh.navigateTab")

    // Global
    static let swooshNewChat            = Notification.Name("ai.swoosh.newChat")
    static let swooshCommandPalette     = Notification.Name("ai.swoosh.commandPalette")
    static let swooshOpenApprovals      = Notification.Name("ai.swoosh.openApprovals")
    static let swooshQuickSearch        = Notification.Name("ai.swoosh.quickSearch")
    static let swooshExplainWhy         = Notification.Name("ai.swoosh.explainWhy")

    // Chat
    static let swooshRegenerateReply    = Notification.Name("ai.swoosh.regenerateReply")
    static let swooshForkChat           = Notification.Name("ai.swoosh.forkChat")
    static let swooshClearChat          = Notification.Name("ai.swoosh.clearChat")
    static let swooshExportMarkdown     = Notification.Name("ai.swoosh.exportMarkdown")
    static let swooshExportJSON         = Notification.Name("ai.swoosh.exportJSON")
    static let swooshAttachFile         = Notification.Name("ai.swoosh.attachFile")
    static let swooshAttachScreenshot   = Notification.Name("ai.swoosh.attachScreenshot")
    static let swooshAttachClipboard    = Notification.Name("ai.swoosh.attachClipboard")
    static let swooshInsertSlashCommand = Notification.Name("ai.swoosh.insertSlashCommand")
    static let swooshRunLastWorkflow    = Notification.Name("ai.swoosh.runLastWorkflow")
    static let swooshRunWorkflow        = Notification.Name("ai.swoosh.runWorkflow")

    // Memories
    static let swooshAddMemory          = Notification.Name("ai.swoosh.addMemory")
    static let swooshSearchMemories     = Notification.Name("ai.swoosh.searchMemories")
    static let swooshReviewCandidates   = Notification.Name("ai.swoosh.reviewCandidates")
    static let swooshApproveAll         = Notification.Name("ai.swoosh.approveAll")
    static let swooshRejectAll          = Notification.Name("ai.swoosh.rejectAll")
    static let swooshRunScout           = Notification.Name("ai.swoosh.runScout")
    static let swooshExportMemories     = Notification.Name("ai.swoosh.exportMemories")
    static let swooshImportMemories     = Notification.Name("ai.swoosh.importMemories")

    // Skills
    static let swooshCreateSkill        = Notification.Name("ai.swoosh.createSkill")
    static let swooshImportSkill        = Notification.Name("ai.swoosh.importSkill")
    static let swooshPromoteSkill       = Notification.Name("ai.swoosh.promoteSkill")
    static let swooshFreezeSkill        = Notification.Name("ai.swoosh.freezeSkill")
    static let swooshReloadBundledSkills = Notification.Name("ai.swoosh.reloadBundledSkills")
    static let swooshExportSkills       = Notification.Name("ai.swoosh.exportSkills")

    // Wallet / Web3
    static let swooshRefreshWallet      = Notification.Name("ai.swoosh.refreshWallet")
    static let swooshCreateWallet       = Notification.Name("ai.swoosh.createWallet")
    static let swooshImportWallet       = Notification.Name("ai.swoosh.importWallet")
    static let swooshViewExplorer       = Notification.Name("ai.swoosh.viewExplorer")
    static let swooshCopyAddress        = Notification.Name("ai.swoosh.copyAddress")

    // Providers
    static let swooshAddProvider        = Notification.Name("ai.swoosh.addProvider")
    static let swooshConfigureKeys      = Notification.Name("ai.swoosh.configureKeys")
    static let swooshTestProvider       = Notification.Name("ai.swoosh.testProvider")
    static let swooshRefreshModels      = Notification.Name("ai.swoosh.refreshModels")
    static let swooshSwitchToMLX        = Notification.Name("ai.swoosh.switchToMLX")
    static let swooshSwitchToFoundation = Notification.Name("ai.swoosh.switchToFoundation")
    static let swooshDownloadModel      = Notification.Name("ai.swoosh.downloadModel")

    // Tools
    static let swooshGrantPermission    = Notification.Name("ai.swoosh.grantPermission")
    static let swooshRevokeAllPermissions = Notification.Name("ai.swoosh.revokeAllPermissions")
    static let swooshRegisterMCP        = Notification.Name("ai.swoosh.registerMCP")
    static let swooshConnectMCP         = Notification.Name("ai.swoosh.connectMCP")
    static let swooshDisconnectMCP      = Notification.Name("ai.swoosh.disconnectMCP")
    static let swooshFilterToolset      = Notification.Name("ai.swoosh.filterToolset")
    static let swooshShowCryptoTools    = Notification.Name("ai.swoosh.showCryptoTools")
    static let swooshShowDeFiTools      = Notification.Name("ai.swoosh.showDeFiTools")

    // Audit
    static let swooshOpenAuditLog       = Notification.Name("ai.swoosh.openAuditLog")
    static let swooshSearchAudit        = Notification.Name("ai.swoosh.searchAudit")
    static let swooshAuditFilterTool    = Notification.Name("ai.swoosh.auditFilterTool")
    static let swooshAuditFilterPerm    = Notification.Name("ai.swoosh.auditFilterPerm")
    static let swooshAuditFilterCrypto  = Notification.Name("ai.swoosh.auditFilterCrypto")
    static let swooshAuditClearFilters  = Notification.Name("ai.swoosh.auditClearFilters")
    static let swooshExportAudit        = Notification.Name("ai.swoosh.exportAudit")
    static let swooshVerifyAnchors      = Notification.Name("ai.swoosh.verifyAnchors")

    // Voice
    static let swooshToggleVoiceNotif   = Notification.Name("ai.swoosh.toggleVoiceNotif")
    static let swooshSwitchOrbTheme     = Notification.Name("ai.swoosh.switchOrbTheme")
    static let swooshNextOrbTheme       = Notification.Name("ai.swoosh.nextOrbTheme")
    static let swooshPrevOrbTheme       = Notification.Name("ai.swoosh.prevOrbTheme")
    static let swooshTogglePTT          = Notification.Name("ai.swoosh.togglePTT")
    static let swooshToggleTTS          = Notification.Name("ai.swoosh.toggleTTS")
    static let swooshSwitchSTT          = Notification.Name("ai.swoosh.switchSTT")
    static let swooshSwitchTTS          = Notification.Name("ai.swoosh.switchTTS")

    // Settings
    static let swooshOpenAppearance     = Notification.Name("ai.swoosh.openAppearance")
    static let swooshChangeTheme        = Notification.Name("ai.swoosh.changeTheme")
    static let swooshConfigureDaemon    = Notification.Name("ai.swoosh.configureDaemon")
    static let swooshRestartDaemon      = Notification.Name("ai.swoosh.restartDaemon")
    static let swooshScoutDepth         = Notification.Name("ai.swoosh.scoutDepth")
    static let swooshManageSecrets      = Notification.Name("ai.swoosh.manageSecrets")
    static let swooshResetSettings      = Notification.Name("ai.swoosh.resetSettings")
}

#endif
