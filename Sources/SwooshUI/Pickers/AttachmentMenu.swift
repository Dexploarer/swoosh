// SwooshUI/Pickers/AttachmentMenu.swift — "+" button + attach sheet
//
// The composer's `+` glyph. Opens a bottom sheet with the actions the
// user can take to enrich the next turn: attach a file, attach a photo,
// surface a Skill, or open an MCP connection. Matches the mobile
// agent pattern documented in the May-2026 SOTA agent UI survey —
// bottom sheets beat popovers on a 6.7" screen because the thumb can
// reach every row.
//
// The actions themselves are wired to callbacks the host passes in so
// `SwooshUI` doesn't need to know about file pickers, skill stores, or
// MCP connectors — those live in their own modules and are plumbed
// through AgentShellView. Default callbacks are no-ops so the sheet
// renders the same in previews and on hosts that don't wire a given
// capability yet.
//
// Navigation chaining: tapping a row that wants to push onto a
// NavigationStack can't fire its handler synchronously — the sheet is
// still mid-dismiss and UIKit silently swallows the push. The earlier
// "dismiss + Task.sleep(120 ms) + action" hack helped intermittently
// but wasn't deterministic. Final pattern: the row stores the chosen
// action in shared @State, the sheet dismisses, and the `.sheet`'s
// onDismiss callback runs the pending action exactly once the sheet
// has fully gone. That's the iOS-blessed sequencing.

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
    /// Action selected inside the sheet, run after the sheet has fully
    /// dismissed. Nil means the user closed the sheet without picking.
    @State private var pendingAction: PendingAction?

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
        .sheet(isPresented: $isPresented, onDismiss: {
            // Sheet has fully closed — safe to push onto the host's
            // NavigationStack now.
            if let pending = pendingAction {
                pendingAction = nil
                pending.run()
            }
        }) {
            AttachmentSheet(
                actions: actions,
                onPick: { kind in
                    pendingAction = PendingAction(kind: kind, actions: actions)
                    isPresented = false
                }
            )
            #if os(iOS)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            #endif
        }
    }
}

/// Concrete action the user picked. Captures the bundle by value so the
/// pending closure stays valid across the dismiss cycle.
private struct PendingAction {
    enum Kind { case file, photo, camera, skills, mcp }
    let kind: Kind
    let actions: AttachmentActions

    @MainActor
    func run() {
        switch kind {
        case .file:   actions.attachFile()
        case .photo:  actions.attachPhoto()
        case .camera: actions.attachCamera()
        case .skills: actions.openSkills()
        case .mcp:    actions.openMCP()
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Sheet body
// ═══════════════════════════════════════════════════════════════════

private struct AttachmentSheet: View {

    let actions: AttachmentActions
    let onPick: (PendingAction.Kind) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(symbol: "doc",     label: "Files",   kind: .file)
                    row(symbol: "photo",   label: "Photos",  kind: .photo)
                    #if os(iOS)
                    row(symbol: "camera",  label: "Camera",  kind: .camera)
                    #endif
                } header: {
                    Label("Attach", systemImage: "paperclip")
                }
                Section {
                    row(symbol: "sparkles", label: "Skills", kind: .skills)
                    row(symbol: "puzzlepiece.extension", label: "MCP Connections", kind: .mcp)
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
    private func row(symbol: String, label: String, kind: PendingAction.Kind) -> some View {
        Button {
            // Stash the user's choice in the host's @State and let the
            // sheet dismiss — the host's onDismiss callback fires the
            // action only after the sheet has fully gone, which is the
            // only reliable moment to push onto a NavigationStack.
            onPick(kind)
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
