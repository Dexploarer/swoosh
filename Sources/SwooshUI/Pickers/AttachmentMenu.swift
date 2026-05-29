// SwooshUI/Pickers/AttachmentMenu.swift — "+" button with expanding gooey popover
//
// The composer's `+` glyph. Instead of opening a full sheet (which
// interrupts the chat flow), the button expands outward with a fluid
// "gooey" animation, showing action buttons that fan out from the
// trigger. Tapping outside or pressing again collapses it.
//
// This pattern keeps the user in-context — they're attaching something
// mid-conversation, not navigating to a separate modal.

import SwiftUI
import SwooshGenerativeUI

// ═══════════════════════════════════════════════════════════════════
// MARK: - Action set
// ═══════════════════════════════════════════════════════════════════

/// Bundle of handlers the host can wire. Any field left as the default
/// no-op simply renders that row as a disabled placeholder.
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
// MARK: - Expanding gooey menu
// ═══════════════════════════════════════════════════════════════════

public struct AttachmentMenu: View {

    public let accent: NeonAccent
    public let actions: AttachmentActions

    @State private var isExpanded = false

    public init(
        accent: NeonAccent = .cyan,
        actions: AttachmentActions = AttachmentActions()
    ) {
        self.accent = accent
        self.actions = actions
    }

    private struct ActionItem: Identifiable {
        let id: String
        let symbol: String
        let label: String
        let action: @MainActor () -> Void
    }

    private var items: [ActionItem] {
        var list = [
            ActionItem(id: "file",   symbol: "doc.fill",           label: "File",    action: actions.attachFile),
            ActionItem(id: "photo",  symbol: "photo.fill",         label: "Photo",   action: actions.attachPhoto),
            ActionItem(id: "skills", symbol: "sparkles",           label: "Skills",  action: actions.openSkills),
            ActionItem(id: "mcp",    symbol: "puzzlepiece.extension.fill", label: "MCP", action: actions.openMCP),
        ]
        #if os(iOS)
        list.insert(
            ActionItem(id: "camera", symbol: "camera.fill", label: "Camera", action: actions.attachCamera),
            at: 2
        )
        #endif
        return list
    }

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            // ── Dismiss backdrop when expanded ──
            if isExpanded {
                VoltPaper.background.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { collapse() }
                    .transition(.opacity)
            }

            // ── Expanded items ──
            if isExpanded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        gooeyItem(item: item, index: index)
                    }
                }
                .padding(.bottom, 44)
                .transition(.opacity.combined(with: .scale(scale: 0.5, anchor: .bottomLeading)))
            }

            // ── Trigger button ──
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: isExpanded ? 12 : 8, style: .continuous)
                        .fill(
                            isExpanded
                            ? SwooshNeonTokens.Accent.cyan.opacity(0.12)
                            : VoltPaper.foreground.opacity(0.04)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: isExpanded ? 12 : 8, style: .continuous)
                                .stroke(
                                    isExpanded
                                    ? SwooshNeonTokens.Accent.cyan.opacity(0.3)
                                    : VoltPaper.foreground.opacity(0.08),
                                    lineWidth: 0.5
                                )
                        )
                        .shadow(
                            color: isExpanded ? SwooshNeonTokens.Accent.cyan.opacity(0.15) : .clear,
                            radius: isExpanded ? 12 : 0
                        )

                    Image(systemName: isExpanded ? "xmark" : "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            isExpanded
                            ? SwooshNeonTokens.Accent.cyan
                            : SwooshNeonTokens.Canvas.text2
                        )
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .frame(width: 36, height: 36)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isExpanded)
            }
            .buttonStyle(.plain)
            .help("Attach a file, photo, skill, or MCP connection")
            .accessibilityLabel(isExpanded ? "Close attachments" : "Attach")
        }
    }

    @ViewBuilder
    private func gooeyItem(item: ActionItem, index: Int) -> some View {
        Button {
            item.action()
            collapse()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(SwooshNeonTokens.Accent.cyan.opacity(0.1))
                    )

                Text(item.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SwooshNeonTokens.Canvas.bg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(VoltPaper.foreground.opacity(0.08), lineWidth: 0.5)
                    )
                    .shadow(color: VoltPaper.background.opacity(0.3), radius: 8, y: 2)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isExpanded ? 1 : 0.3)
        .opacity(isExpanded ? 1 : 0)
        .animation(
            .spring(response: 0.35, dampingFraction: 0.65)
                .delay(Double(index) * 0.04),
            value: isExpanded
        )
    }

    private func collapse() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            isExpanded = false
        }
    }
}
