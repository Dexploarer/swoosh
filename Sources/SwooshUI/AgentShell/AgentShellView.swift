// SwooshUI/AgentShell/AgentShellView.swift — 0.9R Shared shell content
//
// The view the user sees in every host mode. Generative surface is the
// primary content; chat thread is the tail; input row is fixed at bottom.
// Density adjusts per `AgentShellMode` but the layout shape is constant —
// switching hosts shouldn't force the user to re-learn anything.
//
//   ┌─────────────────────────────────┐
//   │   chat thread (scrolls)         │   ← user/agent bubbles, oldest first
//   │   ───────────────────────────   │
//   │   generative surface            │   ← UIRenderer of activeSurfaceID
//   │                                 │
//   ├─────────────────────────────────┤
//   │  [model ⌄]  > _____________  ●  │   ← input row: picker + field + mic
//   └─────────────────────────────────┘

import SwiftUI
import SwooshGenerativeUI
import SwooshModels
import SwooshProviders

public struct AgentShellView: View {

    // MARK: - Inputs

    @Bindable public var shell: AgentShellModel
    public let mode: AgentShellMode

    /// Catalog slice for the model picker. Defaults to **every wired
    /// provider. The picker groups wired cloud routes and local catalog
    /// entries by provider so selection maps to an executable route.
    public let modelCatalog: [UnifiedModelEntry]

    /// Callbacks the composer's "+" attachment menu invokes. Host-supplied;
    /// the defaults are no-ops so the sheet still renders when a host
    /// hasn't wired a given capability.
    public let attachmentActions: AttachmentActions

    public init(
        shell: AgentShellModel,
        mode: AgentShellMode,
        modelCatalog: [UnifiedModelEntry] = UnifiedModelCatalog.interactive,
        attachmentActions: AttachmentActions = AttachmentActions()
    ) {
        self.shell = shell
        self.mode = mode
        self.modelCatalog = modelCatalog
        self.attachmentActions = attachmentActions
    }

    /// Animation scratch for the thinking row's three dots.
    @State private var thinkingPulse: [CGFloat] = [1.0, 1.0, 1.0]

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: SwooshNeonTokens.Spacing.base + 2) {
                        chatThread
                        if shouldShowSurface {
                            generativeSurface
                                .id("surface")
                        }
                    }
                    .padding(SwooshNeonTokens.Spacing.base + (mode == .tray ? 2 : 8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.spring(duration: 0.3, bounce: 0.18), value: shell.messages.count)
                    .animation(.easeInOut(duration: 0.2), value: shell.isAwaitingResponse)
                }
                .onChange(of: shell.messages.count) { _, _ in
                    if let last = shell.messages.last?.id {
                        withAnimation(.spring(duration: 0.25)) {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: shell.isAwaitingResponse) { _, awaiting in
                    if awaiting {
                        withAnimation(.spring(duration: 0.25)) {
                            proxy.scrollTo("thinking", anchor: .bottom)
                        }
                    }
                }
            }

            inputRow
        }
        .background(SwooshNeonTokens.Canvas.bg)
        .modifier(SizeConstraints(mode: mode))
    }

    // MARK: - Chat thread

    @ViewBuilder
    private var chatThread: some View {
        if shell.messages.isEmpty && !shouldShowSurface && !shell.isAwaitingResponse {
            emptyState
        } else {
            ForEach(shell.messages) { msg in
                bubble(for: msg)
                    .id(msg.id)
            }
            if shell.isAwaitingResponse {
                thinkingRow
                    .id("thinking")
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        HStack(alignment: .firstTextBaseline, spacing: SwooshNeonTokens.Spacing.base) {
            EmptyStateDot()
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                Text("DETOUR")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                Text("Ask anything.")
                    .font(.system(size: bubbleFontSize, weight: .medium))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, SwooshNeonTokens.Spacing.base)
    }

    @ViewBuilder
    private func bubble(for msg: AgentShellMessage) -> some View {
        let isUser = msg.role == .user
        HStack(alignment: .top, spacing: SwooshNeonTokens.Spacing.base) {
            if isUser {
                Spacer(minLength: 24)
                Text(msg.text)
                    .font(.system(size: bubbleFontSize))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                    .padding(.horizontal, SwooshNeonTokens.Spacing.base + 2)
                    .padding(.vertical, SwooshNeonTokens.Spacing.micro + 2)
                    .neonTile(.cyan, state: .focus, shape: .card)
            } else {
                // Agent text reads as flowing prose, not a contained
                // bubble — keeps the channel calm and lets the eye
                // settle on content rather than chrome.
                VStack(alignment: .leading, spacing: 4) {
                    Text("DETOUR")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                    Text(msg.text)
                        .font(.system(size: bubbleFontSize))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
    }

    @ViewBuilder
    private var thinkingRow: some View {
        HStack(alignment: .center, spacing: SwooshNeonTokens.Spacing.base) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AGENT")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(SwooshNeonTokens.Accent.cyan)
                            .frame(width: 5, height: 5)
                            .opacity(0.7)
                            .shadow(color: SwooshNeonTokens.Accent.cyan.opacity(0.5), radius: 3)
                            .scaleEffect(thinkingPulse[i])
                    }
                }
            }
            Spacer()
        }
        .onAppear {
            for i in 0..<3 {
                withAnimation(
                    .easeInOut(duration: 0.45)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.12)
                ) {
                    thinkingPulse[i] = 1.6
                }
            }
        }
        .transition(.opacity)
    }

    // MARK: - Generative surface

    private var shouldShowSurface: Bool {
        shell.surfaceHost.surfaces[shell.activeSurfaceID] != nil
    }

    @ViewBuilder
    private var generativeSurface: some View {
        GenerativeSurfaceView(
            host: shell.surfaceHost,
            surfaceID: shell.activeSurfaceID
        )
        .padding(.top, SwooshNeonTokens.Spacing.micro)
    }

    // MARK: - Input row

    private var inputRow: some View {
        VStack(spacing: SwooshNeonTokens.Spacing.micro) {
            // Top metadata strip — sync badge + listening transcript
            HStack(spacing: SwooshNeonTokens.Spacing.base) {
                SyncBadge(state: shell.syncState)
                if shell.voice == .listening, !shell.speech.transcript.isEmpty {
                    Text(shell.speech.transcript)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Main input row.
            // [+] opens the attachment sheet (Files / Photos / Skills /
            // MCP). [⚙] opens the unified picker (Brain / Listen / Speak /
            // Music). Both are tiny 36×36 glyphs that defer their content
            // to bottom sheets so the composer stays narrow.
            HStack(spacing: SwooshNeonTokens.Spacing.micro + 2) {
                AttachmentMenu(accent: .cyan, actions: attachmentActions)
                unifiedPicker
                inputField
                // On iPhone the host (AgentRoot toolbar + bottom voice
                // pill) owns the mic affordance; rendering one here too
                // would mean two mics on screen at once.
                if mode != .phone {
                    micButton
                }
            }
        }
        .padding(.horizontal, SwooshNeonTokens.Spacing.base + 2)
        .padding(.vertical, SwooshNeonTokens.Spacing.base)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(SwooshNeonTokens.Line.rule)
                .frame(height: 0.5)
        }
        .background(SwooshNeonTokens.Canvas.bg)
    }

    private var unifiedPicker: some View {
        UnifiedAgentPicker(
            models: modelCatalog,
            selectedModelID: $shell.selectedModelID,
            effort: $shell.selectedEffort
        )
    }

    private var inputField: some View {
        TextField("Message", text: $shell.input)
            .textFieldStyle(.plain)
            .foregroundStyle(SwooshNeonTokens.Canvas.text1)
            .font(.system(size: bubbleFontSize))
            .padding(.horizontal, SwooshNeonTokens.Spacing.base + 2)
            .padding(.vertical, SwooshNeonTokens.Spacing.micro + 2)
            .neonTile(.cyan, state: .idle, shape: .card)
            .onSubmit { Task { await shell.submit() } }
    }

    @ViewBuilder
    private var micButton: some View {
        let listening = shell.voice == .listening
        Button {
            if listening { shell.stopListening() } else { shell.startListening() }
        } label: {
            ZStack {
                ListeningPulse(active: listening)
                if listening {
                    VoiceWaveformView(
                        level: shell.speech.audioLevel,
                        active: true,
                        barCount: 6
                    )
                    .frame(width: 28)
                } else {
                    Image(systemName: "mic")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                }
            }
            .frame(width: 36, height: 36)
            .neonTile(.cyan, state: listening ? .active : .idle, shape: .card)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(listening ? "Stop listening" : "Start listening")
    }

    // MARK: - Density

    private var bubbleFontSize: CGFloat {
        switch mode {
        case .tray, .pill: return 13
        case .window:      return 14
        case .phone:       return 15
        }
    }
}

// MARK: - Per-mode size constraints

/// iPhone needs `.frame(maxWidth: .infinity, maxHeight: .infinity)` (no
/// minWidth/minHeight clamps) so it fills whatever the navigation stack
/// gives it. The Mac modes get specific minimums so their windows /
/// popovers don't collapse below usable sizes.
private struct SizeConstraints: ViewModifier {
    let mode: AgentShellMode

    func body(content: Content) -> some View {
        switch mode {
        case .phone:
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        case .tray:
            content.frame(minWidth: 360, minHeight: 320)
        case .pill:
            content.frame(minWidth: 440, minHeight: 56)
        case .window:
            content.frame(minWidth: 720, minHeight: 560)
        }
    }
}
