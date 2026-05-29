// SwooshUI/Interactions/MenuActionHandler.swift — E2E menu action wiring
//
// A ViewModifier that observes every Notification.Name from EditMenu.swift
// and performs the corresponding real action on the shell, voice, or view
// state. Applied once on the DashboardView.
//
// Actions that require a file panel or confirmation dialog set @State
// flags on the modifier, which trigger .fileExporter / .alert sheets.

#if os(macOS)

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SwooshGenerativeUI

// ═══════════════════════════════════════════════════════════════════
// MARK: - Modifier
// ═══════════════════════════════════════════════════════════════════

struct MenuActionHandlerModifier: ViewModifier {
    @Bindable var shell: AgentShellModel
    var voice: VoiceMode?
    @Binding var selectedTab: DashboardTab
    @Binding var sidebarVisible: Bool

    // File export state
    @State private var showExportMarkdown = false
    @State private var showExportJSON = false
    @State private var showAttachFile = false
    @State private var exportContent = ""
    @State private var exportFileName = "chat"

    // Confirmation dialogs
    @State private var showClearConfirm = false
    @State private var showResetConfirm = false
    @State private var showRevokeConfirm = false

    func body(content: Content) -> some View {
        content
            // ── View / Navigation ────────────────────────────
            .onReceive(note(.swooshToggleSidebar)) { _ in
                withAnimation(.easeOut(duration: 0.22)) {
                    sidebarVisible.toggle()
                }
            }
            .onReceive(note(.swooshNavigateTab)) { notif in
                if let raw = notif.object as? String,
                   let tab = DashboardTab(rawValue: raw) {
                    selectedTab = tab
                }
            }

            // ── Chat: New / Clear / Regenerate / Fork ────────
            .onReceive(note(.swooshNewChat)) { _ in
                shell.clearConversation()
                selectedTab = .chat
            }
            .onReceive(note(.swooshRegenerateReply)) { _ in
                guard selectedTab == .chat else { return }
                // Remove the last agent message and re-submit the last user message
                if let lastAgent = shell.messages.lastIndex(where: { $0.role == .agent }) {
                    shell.messages.remove(at: lastAgent)
                    if let lastUser = shell.messages.last(where: { $0.role == .user }) {
                        shell.input = lastUser.text
                        Task { await shell.submit() }
                    }
                }
            }
            .onReceive(note(.swooshForkChat)) { _ in
                // Fork = duplicate the current conversation into a fresh session
                // For now, just show a system message indicating the fork point
                shell.messages.append(.init(
                    role: .agent,
                    text: "── conversation forked ──"
                ))
            }
            .onReceive(note(.swooshClearChat)) { _ in
                showClearConfirm = true
            }
            .alert("Clear Conversation?", isPresented: $showClearConfirm) {
                Button("Clear", role: .destructive) {
                    shell.clearConversation()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all messages in the current session.")
            }

            // ── Chat: Export ─────────────────────────────────
            .onReceive(note(.swooshExportMarkdown)) { _ in
                let md = exportAsMarkdown()
                saveToFile(content: md, ext: "md", name: "swoosh-chat")
            }
            .onReceive(note(.swooshExportJSON)) { _ in
                let json = exportAsJSON()
                saveToFile(content: json, ext: "json", name: "swoosh-chat")
            }

            // ── Chat: Attach ─────────────────────────────────
            .onReceive(note(.swooshAttachFile)) { _ in
                attachFileFromPanel()
            }
            .onReceive(note(.swooshAttachScreenshot)) { _ in
                attachScreenshot()
            }
            .onReceive(note(.swooshAttachClipboard)) { _ in
                attachClipboard()
            }

            // ── Chat: Commands / Workflows ───────────────────
            .onReceive(note(.swooshInsertSlashCommand)) { _ in
                selectedTab = .chat
                shell.input = "/"
            }
            .onReceive(note(.swooshRunLastWorkflow)) { _ in
                shell.input = "/run-last"
                Task { await shell.submit() }
            }
            .onReceive(note(.swooshRunWorkflow)) { _ in
                selectedTab = .chat
                shell.input = "/workflow "
            }

            // ── Chat: Command Palette ────────────────────────
            .onReceive(note(.swooshCommandPalette)) { _ in
                selectedTab = .chat
                shell.input = "/"
            }
            .onReceive(note(.swooshExplainWhy)) { _ in
                selectedTab = .chat
                shell.input = "/why"
                Task { await shell.submit() }
            }

            // ── Edit: Pin / Send to Chat ─────────────────────
            .onReceive(note(.swooshPinSelection)) { _ in
                if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
                    shell.input = "/memory add \(text)"
                    Task { await shell.submit() }
                }
            }
            .onReceive(note(.swooshSendToChat)) { _ in
                if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
                    selectedTab = .chat
                    shell.input = text
                }
            }

            // ── Memories ─────────────────────────────────────
            .onReceive(note(.swooshAddMemory)) { _ in
                selectedTab = .memories
                // Focus the add-memory flow by injecting a chat command
                shell.input = "/memory add "
            }
            .onReceive(note(.swooshSearchMemories)) { _ in
                selectedTab = .memories
                shell.input = "/memory search "
            }
            .onReceive(note(.swooshReviewCandidates)) { _ in
                selectedTab = .memories
                shell.input = "/memory candidates"
                Task { await shell.submit() }
            }
            .onReceive(note(.swooshApproveAll)) { _ in
                shell.input = "/memory approve-all"
                Task { await shell.submit() }
            }
            .onReceive(note(.swooshRejectAll)) { _ in
                shell.input = "/memory reject-all"
                Task { await shell.submit() }
            }
            .onReceive(note(.swooshRunScout)) { _ in
                shell.input = "/scout run"
                Task { await shell.submit() }
            }
            .onReceive(note(.swooshExportMemories)) { _ in
                shell.input = "/memory export"
                Task { await shell.submit() }
            }
            .onReceive(note(.swooshImportMemories)) { _ in
                attachFileForImport(type: "memories")
            }

            // ── Skills ───────────────────────────────────────
            .onReceive(note(.swooshCreateSkill)) { _ in
                selectedTab = .skills
                shell.input = "/skill propose "
            }
            .onReceive(note(.swooshImportSkill)) { _ in
                attachFileForImport(type: "skill")
            }
            .onReceive(note(.swooshPromoteSkill)) { _ in
                shell.input = "/skill approve "
            }
            .onReceive(note(.swooshFreezeSkill)) { _ in
                shell.input = "/skill freeze "
            }
            .onReceive(note(.swooshReloadBundledSkills)) { _ in
                shell.input = "/skill reload-bundled"
                Task { await shell.submit() }
            }
            .onReceive(note(.swooshExportSkills)) { _ in
                shell.input = "/skill export"
                Task { await shell.submit() }
            }

            // ── Providers ────────────────────────────────────
            .onReceive(note(.swooshAddProvider)) { _ in
                selectedTab = .models
                shell.input = "/provider add "
            }
            .onReceive(note(.swooshConfigureKeys)) { _ in
                selectedTab = .models
                shell.input = "/provider keys"
                Task { await shell.submit() }
            }
            .onReceive(note(.swooshTestProvider)) { _ in
                shell.input = "/provider test"
                Task { await shell.submit() }
            }
            .onReceive(note(.swooshRefreshModels)) { _ in
                shell.input = "/model list --refresh"
                Task { await shell.submit() }
            }
            .onReceive(note(.swooshSwitchToMLX)) { _ in
                shell.input = "/model use mlx"
                Task { await shell.submit() }
            }
            .onReceive(note(.swooshSwitchToFoundation)) { _ in
                shell.input = "/model use apple-foundation"
                Task { await shell.submit() }
            }
            .onReceive(note(.swooshDownloadModel)) { _ in
                selectedTab = .models
                shell.input = "/model download "
            }

            // ── Tools ────────────────────────────────────────
            .onReceive(note(.swooshGrantPermission)) { _ in
                selectedTab = .tools
                shell.input = "/permissions grant "
            }
            .onReceive(note(.swooshRevokeAllPermissions)) { _ in
                showRevokeConfirm = true
            }
            .alert("Revoke All Permissions?", isPresented: $showRevokeConfirm) {
                Button("Revoke All", role: .destructive) {
                    shell.input = "/permissions revoke-all"
                    Task { await shell.submit() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will revoke every granted permission. Tools will need re-approval.")
            }
            .onReceive(note(.swooshRegisterMCP)) { _ in
                selectedTab = .tools
                shell.input = "/mcp register "
            }
            .onReceive(note(.swooshConnectMCP)) { _ in
                shell.input = "/mcp connect"
                Task { await shell.submit() }
            }
            .onReceive(note(.swooshDisconnectMCP)) { _ in
                shell.input = "/mcp disconnect"
                Task { await shell.submit() }
            }
            .onReceive(note(.swooshFilterToolset)) { _ in
                selectedTab = .tools
            }
            .onReceive(note(.swooshShowCryptoTools)) { _ in
                selectedTab = .tools
                shell.input = "/tools list --toolset evm,solana,jupiter,hyperliquid,uniswap"
                Task { await shell.submit() }
            }
            .onReceive(note(.swooshShowDeFiTools)) { _ in
                selectedTab = .tools
                shell.input = "/tools list --toolset jupiter,hyperliquid,uniswap"
                Task { await shell.submit() }
            }

            // ── Audit ────────────────────────────────────────
            .onReceive(note(.swooshOpenAuditLog)) { _ in
                selectedTab = .audit
            }
            .onReceive(note(.swooshSearchAudit)) { _ in
                selectedTab = .audit
                shell.input = "/audit search "
            }
            .onReceive(note(.swooshAuditFilterTool)) { _ in
                selectedTab = .audit
                shell.input = "/audit filter tool-calls"
                Task { await shell.submit() }
            }
            .onReceive(note(.swooshAuditFilterPerm)) { _ in
                selectedTab = .audit
                shell.input = "/audit filter permissions"
                Task { await shell.submit() }
            }
            .onReceive(note(.swooshAuditFilterCrypto)) { _ in
                selectedTab = .audit
                shell.input = "/audit filter crypto"
                Task { await shell.submit() }
            }
            .onReceive(note(.swooshAuditClearFilters)) { _ in
                selectedTab = .audit
                shell.input = "/audit filter clear"
                Task { await shell.submit() }
            }
            .onReceive(note(.swooshExportAudit)) { _ in
                shell.input = "/audit export"
                Task { await shell.submit() }
            }
            .onReceive(note(.swooshVerifyAnchors)) { _ in
                shell.input = "/audit verify-anchors"
                Task { await shell.submit() }
            }

            // ── Voice ────────────────────────────────────────
            .onReceive(note(.swooshToggleVoiceNotif)) { _ in
                voice?.toggle()
            }
            .onReceive(note(.swooshSwitchOrbTheme)) { _ in
                selectedTab = .voice
            }
            .onReceive(note(.swooshNextOrbTheme)) { _ in
                cycleOrbTheme(forward: true)
            }
            .onReceive(note(.swooshPrevOrbTheme)) { _ in
                cycleOrbTheme(forward: false)
            }
            .onReceive(note(.swooshTogglePTT)) { _ in
                voice?.pushToTalk.toggle()
            }
            .onReceive(note(.swooshToggleTTS)) { _ in
                voice?.speakReplies.toggle()
            }
            .onReceive(note(.swooshSwitchSTT)) { _ in
                selectedTab = .voice
            }
            .onReceive(note(.swooshSwitchTTS)) { _ in
                selectedTab = .voice
            }

            // ── Settings ─────────────────────────────────────
            .onReceive(note(.swooshOpenAppearance)) { _ in
                selectedTab = .settings
            }
            .onReceive(note(.swooshChangeTheme)) { _ in
                selectedTab = .settings
            }
            .onReceive(note(.swooshConfigureDaemon)) { _ in
                selectedTab = .settings
            }
            .onReceive(note(.swooshRestartDaemon)) { _ in
                shell.input = "/daemon restart"
                Task { await shell.submit() }
            }
            .onReceive(note(.swooshScoutDepth)) { _ in
                selectedTab = .settings
            }
            .onReceive(note(.swooshManageSecrets)) { _ in
                selectedTab = .settings
                shell.input = "/secrets list"
                Task { await shell.submit() }
            }
            .onReceive(note(.swooshResetSettings)) { _ in
                showResetConfirm = true
            }
            .alert("Reset All Settings?", isPresented: $showResetConfirm) {
                Button("Reset", role: .destructive) {
                    shell.input = "/settings reset-all"
                    Task { await shell.submit() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will reset all Swoosh settings to their defaults. Memories and audit history are preserved.")
            }

            // ── Approvals ────────────────────────────────────
            .onReceive(note(.swooshOpenApprovals)) { _ in
                selectedTab = .approvals
            }
            .onReceive(note(.swooshQuickSearch)) { _ in
                selectedTab = .chat
                shell.input = "/search "
            }
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Helpers
    // ═══════════════════════════════════════════════════════════════

    /// Shorthand for NotificationCenter publisher.
    private func note(_ name: Notification.Name) -> NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: name)
    }

    // ── Export ────────────────────────────────────────────────────

    private func exportAsMarkdown() -> String {
        var lines: [String] = ["# Swoosh Chat Export", ""]
        for msg in shell.messages {
            let prefix = msg.role == .user ? "**You**" : "**Swoosh**"
            lines.append("\(prefix): \(msg.text)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func exportAsJSON() -> String {
        let records = shell.messages.map { msg in
            ["role": msg.role == .user ? "user" : "agent", "text": msg.text]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }

    private func saveToFile(content: String, ext: String, name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(name).\(ext)"
        panel.allowedContentTypes = ext == "md"
            ? [UTType.plainText]
            : [UTType.json]
        panel.begin { result in
            if result == .OK, let url = panel.url {
                try? content.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    // ── Attach ───────────────────────────────────────────────────

    private func attachFileFromPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { result in
            if result == .OK, let url = panel.url,
               let content = try? String(contentsOf: url, encoding: .utf8) {
                let name = url.lastPathComponent
                selectedTab = .chat
                shell.input = "```\(name)\n\(content.prefix(8000))\n```"
            }
        }
    }

    private func attachScreenshot() {
        // Use macOS screencapture CLI to grab a selection
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        let tmpPath = NSTemporaryDirectory() + "swoosh-screenshot-\(Int(Date().timeIntervalSince1970)).png"
        task.arguments = ["-i", "-s", tmpPath]
        try? task.run()
        task.waitUntilExit()
        if FileManager.default.fileExists(atPath: tmpPath) {
            selectedTab = .chat
            shell.messages.append(.init(
                role: .user,
                text: "📎 Screenshot attached: \(tmpPath)"
            ))
        }
    }

    private func attachClipboard() {
        if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
            selectedTab = .chat
            shell.input = text
        }
    }

    private func attachFileForImport(type: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json, .plainText]
        panel.begin { result in
            if result == .OK, let url = panel.url {
                shell.input = "/\(type) import \(url.path)"
                Task { await shell.submit() }
            }
        }
    }

    // ── Orb theme cycling ────────────────────────────────────────

    private func cycleOrbTheme(forward: Bool) {
        let key = "selectedOrbTheme"
        let themes = ["aurora", "cosmic", "ocean", "sunset", "neon", "glacier", "ember", "phantom"]
        let current = UserDefaults.standard.string(forKey: key) ?? "aurora"
        guard let idx = themes.firstIndex(of: current) else { return }
        let next = forward
            ? themes[(idx + 1) % themes.count]
            : themes[(idx - 1 + themes.count) % themes.count]
        UserDefaults.standard.set(next, forKey: key)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - View extension
// ═══════════════════════════════════════════════════════════════════

extension View {
    func menuActionHandler(
        shell: AgentShellModel,
        voice: VoiceMode?,
        selectedTab: Binding<DashboardTab>,
        sidebarVisible: Binding<Bool>
    ) -> some View {
        modifier(MenuActionHandlerModifier(
            shell: shell,
            voice: voice,
            selectedTab: selectedTab,
            sidebarVisible: sidebarVisible
        ))
    }
}

#endif
