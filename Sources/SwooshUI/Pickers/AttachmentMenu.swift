// SwooshUI/Pickers/AttachmentMenu.swift — "+" button + attach sheet
//
// The composer's `+` glyph. Opens a bottom sheet with the actions the
// user can take to enrich the next turn: attach a file, attach a photo,
// surface a Skill, or open an MCP connection. Matches the Gemini /
// ChatGPT pattern documented in the May-2026 SOTA agent UI survey —
// bottom sheets beat popovers on a 6.7" screen because the thumb can
// reach every row.
//
// The actions themselves are wired to callbacks the host passes in so
// `SwooshUI` doesn't need to know about file pickers, skill stores, or
// MCP connectors — those live in their own modules and are plumbed
// through AgentShellView. Default callbacks are no-ops so the sheet
// renders the same in previews and on hosts that don't wire a given
// capability yet.

import SwiftUI
import SwooshGenerativeUI

// ═══════════════════════════════════════════════════════════════════
// MARK: - Action set
// ═══════════════════════════════════════════════════════════════════

/// Bundle of handlers the host can wire. Any field left as the default
/// no-op simply renders that row as a disabled placeholder — useful while
/// the daemon side of a given capability is still being wired.
public struct AttachmentActions: Sendable {
    public var attachFile:     @MainActor () -> Void
    public var attachPhoto:    @MainActor () -> Void
    public var attachCamera:   @MainActor () -> Void
    public var openSkills:     @MainActor () -> Void
    public var openMCP:        @MainActor () -> Void

    public init(
        attachFile:   @MainActor @escaping () -> Void = {},
        attachPhoto:  @MainActor @escaping () -> Void = {},
        attachCamera: @MainActor @escaping () -> Void = {},
        openSkills:   @MainActor @escaping () -> Void = {},
        openMCP:      @MainActor @escaping () -> Void = {}
    ) {
        self.attachFile = attachFile
        self.attachPhoto = attachPhoto
        self.attachCamera = attachCamera
        self.openSkills = openSkills
        self.openMCP = openMCP
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Trigger
// ═══════════════════════════════════════════════════════════════════

public struct AttachmentMenu: View {

    public let accent: NeonAccent
    public let actions: AttachmentActions

    @State private var isPresented = false

    public init(
        accent: NeonAccent = .cyan,
        actions: AttachmentActions = AttachmentActions()
    ) {
        self.accent = accent
        self.actions = actions
    }

    public var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                .frame(width: 36, height: 36)
                .neonTile(accent, state: .idle, shape: .card)
        }
        .buttonStyle(.plain)
        .help("Attach a file, photo, skill, or MCP connection")
        .accessibilityLabel("Attach")
        .sheet(isPresented: $isPresented) {
            AttachmentSheet(actions: actions, dismiss: { isPresented = false })
                #if os(iOS)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                #endif
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Sheet body
// ═══════════════════════════════════════════════════════════════════

private struct AttachmentSheet: View {

    let actions: AttachmentActions
    let dismiss: @MainActor () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(symbol: "doc",     label: "Files",   action: actions.attachFile)
                    row(symbol: "photo",   label: "Photos",  action: actions.attachPhoto)
                    #if os(iOS)
                    row(symbol: "camera",  label: "Camera",  action: actions.attachCamera)
                    #endif
                } header: {
                    Label("Attach", systemImage: "paperclip")
                }
                Section {
                    row(symbol: "sparkles", label: "Skills", action: actions.openSkills)
                    row(symbol: "puzzlepiece.extension", label: "MCP Connections", action: actions.openMCP)
                } header: {
                    Label("Capabilities", systemImage: "wand.and.stars")
                } footer: {
                    Text("Skills are reusable prompts. MCP connections let the agent talk to external tools.")
                }
            }
            .navigationTitle("Attach")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                #endif
            }
        }
    }

    @ViewBuilder
    private func row(symbol: String, label: String, action: @escaping @MainActor () -> Void) -> some View {
        Button {
            // Dismiss first, then fire the action on the next runloop tick
            // so a sheet → NavigationStack push doesn't race the dismiss.
            // Tapping "Skills" was navigating before the sheet finished
            // closing on iOS 26, which UIKit silently swallowed.
            dismiss()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                action()
            }
        } label: {
            HStack {
                Image(systemName: symbol)
                    .frame(width: 24)
                    .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                Text(label)
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text2)
            }
        }
        .buttonStyle(.plain)
    }
}
