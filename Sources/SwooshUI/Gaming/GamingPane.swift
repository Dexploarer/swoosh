// SwooshUI/Gaming/GamingPane.swift — NitroGen gaming dashboard pane — 0.9T
//
// Two-column gaming dashboard: left column for session setup (window
// picker, model status, controls), right column for live preview and
// status. Full-width key-mapping disclosure group at the bottom.
// Pure neon language — black canvas, cyan hairlines, glow elevation.

#if os(macOS)

import SwiftUI
import SwooshGenerativeUI
import SwooshCloudGaming

// Notification names matching GamingNavigationTools.swift in SwooshToolsets.
// Redeclared here because SwooshUI must not import SwooshToolsets (would create
// a circular dependency). Both modules use the same string constants.
private extension Notification.Name {
    static let swooshGamingSearchGame    = Notification.Name("ai.swoosh.gaming.searchGame")
    static let swooshGamingClickElement  = Notification.Name("ai.swoosh.gaming.clickElement")
    static let swooshGamingTypeText      = Notification.Name("ai.swoosh.gaming.typeText")
    static let swooshGamingNavigateURL   = Notification.Name("ai.swoosh.gaming.navigateURL")
    static let swooshGamingScreenshotWeb = Notification.Name("ai.swoosh.gaming.screenshotWeb")
    static let swooshGamingSelectPlatform = Notification.Name("ai.swoosh.gaming.selectPlatform")
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Gaming pane
// ═══════════════════════════════════════════════════════════════════

public struct GamingPane: View {

    // ── Persisted settings ──────────────────────────────────────────
    @AppStorage("swoosh.gaming.fps") private var fpsTarget: Double = 30
    @AppStorage("swoosh.gaming.mouseSensitivity") private var mouseSensitivity: Double = 5
    @AppStorage("swoosh.gaming.useWASD") private var useWASD: Bool = true
    @AppStorage("swoosh.gaming.blockMenuButtons") private var blockMenuButtons: Bool = true
    @AppStorage("swoosh.gaming.dryRun") private var dryRun: Bool = false

    // ── Local state ─────────────────────────────────────────────────
    @State private var windowTitle: String = ""
    @State private var bundleID: String = ""
    @State private var isRunning: Bool = false
    @State private var stepCount: Int = 0
    @State private var currentFPS: Double = 0
    @State private var isRecording: Bool = false
    @State private var showKeyMappingModal: Bool = false
    @State private var keyMappings: [KeyMapping] = KeyMapping.defaults
    @State private var pulseAnimation: Bool = false
    @State private var pressedButtons: Set<ControllerButton> = []
    @Binding var manualControllerLayout: InteractiveControllerView.Layout?

    // ── Agent voice (real VoiceMode, injected from parent) ────
    var voiceMode: VoiceMode

    // ── Cloud gaming state ──────────────────────────────────────────
    @Binding var selectedSource: GameSource?
    @State private var streamStatus: StreamStatus = .disconnected
    @State private var webBridge: WebGameBridge?

    // ── Native gaming state ────────────────────────────────────────
    @State private var discoveredWindows: [(id: UInt32, title: String, bundleID: String)] = []
    @State private var selectedWindowID: UInt32?
    @State private var isScanning: Bool = false

    public init(
        selectedSource: Binding<GameSource?>,
        manualControllerLayout: Binding<InteractiveControllerView.Layout?>,
        showSettingsModal: Binding<Bool>,
        voiceMode: VoiceMode
    ) {
        self._selectedSource = selectedSource
        self._manualControllerLayout = manualControllerLayout
        self._showSettingsModal = showSettingsModal
        self.voiceMode = voiceMode
    }

    @Binding var showSettingsModal: Bool

    public var body: some View {
        ZStack {
            // ── LAYER 0: Full-bleed stream / placeholder ─────
            fullBleedPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            // ── LAYER 1: Controller overlay (bottom-left) ────
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    controllerOverlay
                    Spacer()
                }
            }
            .padding(.leading, 12)
            .padding(.bottom, 12)

            // ── LAYER 2: Power + Keyboard (bottom-right) ─────
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    HStack(spacing: 12) {
                        // Keyboard mapping
                        Button {
                            showKeyMappingModal = true
                        } label: {
                            Image(systemName: "keyboard")
                                .font(.system(size: 13))
                                .foregroundStyle(VoltPaper.foreground.opacity(0.7))
                                .padding(8)
                                .background(Circle().fill(VoltPaper.foreground.opacity(0.1)))
                        }
                        .buttonStyle(.plain)

                        // Power button
                        powerButton
                    }
                }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 16)

            // ── LAYER 3: Status dot (top-right) ──────────────
            VStack {
                HStack {
                    Spacer()
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 10, height: 10)
                        .shadow(color: statusDotColor.opacity(0.6), radius: isRunning || isRecording ? 6 : 0)
                        .animation(.easeInOut(duration: 0.4), value: statusDotColor)
                }
                .padding(.top, 14)
                .padding(.trailing, 16)
                Spacer()
            }

            // ── LAYER 4: Floating agent orb ─────────────────
            GamingAgentOrb(
                voiceMode: voiceMode,
                isNitroGenRunning: isRunning
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VoltPaper.background)
        .onChange(of: selectedSource) { _, newSource in
            webBridge = nil
            streamStatus = .disconnected
            discoveredWindows = []
            selectedWindowID = nil
            switch newSource {
            case .web(let svc):
                webBridge = WebGameBridge(service: svc)
            case .native(let src):
                scanForWindows(source: src)
            case .none:
                break
            }
        }
        .sheet(isPresented: $showKeyMappingModal) {
            keyMappingModalContent
        }
        .sheet(isPresented: $showSettingsModal) {
            settingsModalContent
        }
        .onAppear {
            wireGamingSendHandler()
        }
        // ── Navigation tool notification observers ───────────
        .onReceive(NotificationCenter.default.publisher(for: .swooshGamingSearchGame)) { note in
            handleSearchGame(note)
        }
        .onReceive(NotificationCenter.default.publisher(for: .swooshGamingClickElement)) { note in
            handleClickElement(note)
        }
        .onReceive(NotificationCenter.default.publisher(for: .swooshGamingTypeText)) { note in
            handleTypeText(note)
        }
        .onReceive(NotificationCenter.default.publisher(for: .swooshGamingNavigateURL)) { note in
            handleNavigateURL(note)
        }
        .onReceive(NotificationCenter.default.publisher(for: .swooshGamingSelectPlatform)) { note in
            handleSelectPlatform(note)
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Full-bleed stream content (no card wrapper)
    // ─────────────────────────────────────────────────────────────────

    @ViewBuilder
    private var fullBleedPreview: some View {
        if let bridge = webBridge, let svc = selectedCloudService {
            ZStack {
                WebStreamView(
                    service: svc,
                    bridge: bridge,
                    onStatusChange: { newStatus in
                        streamStatus = newStatus
                    }
                )

                // Status overlay (top-right)
                VStack {
                    HStack {
                        Spacer()
                        if streamStatus != .playing {
                            Text(streamStatus.rawValue.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(VoltPaper.foreground.opacity(0.5))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(VoltPaper.background.opacity(0.4)))
                                .padding(12)
                        }
                    }
                    Spacer()
                }
            }
        } else {
            // Empty state — subtle gradient placeholder
            ZStack {
                LinearGradient(
                    colors: [
                        VoltPaper.surface,
                        VoltPaper.muted,
                        VoltPaper.background
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(spacing: 14) {
                    Image(systemName: "display")
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [controllerBrandColor.opacity(0.3), controllerBrandColor.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Text(selectedSource == nil ? "Select a platform to begin" : "Connecting…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(VoltPaper.foreground.opacity(0.3))
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Power button
    // ─────────────────────────────────────────────────────────────────

    private var powerButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                isRunning.toggle()
                if isRunning {
                    stepCount = 0
                    currentFPS = fpsTarget
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(
                        isRunning
                            ? VoltPaper.destructive.opacity(0.2)
                            : VoltPaper.accent.opacity(0.15)
                    )
                    .frame(width: 34, height: 34)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isRunning ? VoltPaper.destructive.opacity(0.6) : VoltPaper.accent.opacity(0.5),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(
                        color: (isRunning ? VoltPaper.destructive : VoltPaper.accent).opacity(0.5),
                        radius: isRunning ? 8 : 4
                    )

                Image(systemName: "power")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isRunning ? VoltPaper.destructive : VoltPaper.accent)
            }
        }
        .buttonStyle(.plain)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Controller overlay (bottom-left, semi-transparent)
    // ─────────────────────────────────────────────────────────────────

    private var controllerOverlay: some View {
        InteractiveControllerView(
            layout: controllerLayout,
            accentColor: controllerBrandColor,
            pressedButtons: $pressedButtons
        )
        .frame(width: 240, height: 240)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Status dot
    // ─────────────────────────────────────────────────────────────────

    private var statusDotColor: Color {
        if isRecording || isRunning {
            return VoltPaper.destructive
        } else if selectedSource != nil && (streamStatus == .playing || streamStatus == .paused) {
            return VoltPaper.accent
        } else if selectedSource != nil {
            return VoltPaper.mutedFg  // grey — source selected but not yet connected
        } else {
            return VoltPaper.mutedFg.opacity(0.6)   // dim grey — nothing selected
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Settings modal (everything else)
    // ─────────────────────────────────────────────────────────────────

    private var settingsModalContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(controllerBrandColor)
                    Text("Session Settings")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                }
                Spacer()
                Button {
                    showSettingsModal = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider().opacity(0.15)

            ScrollView {
                VStack(spacing: 16) {
                    // Window picker / Cloud info / Native setup
                    if isCloudSource {
                        cloudInfoCard
                    } else if isNativeSource {
                        nativeSetupCard
                    } else {
                        windowPickerCard
                    }

                    // Model status
                    modelStatusCard

                    // Controls
                    controlsCard

                    // Status
                    statusCard
                }
                .padding(20)
            }

            Divider().opacity(0.15)

            // Done button
            HStack {
                Spacer()
                Button {
                    showSettingsModal = false
                } label: {
                    Text("Done")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(VoltPaper.foreground)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(controllerBrandColor))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .frame(width: 520, height: 600)
        .background(SwooshNeonTokens.Canvas.bg)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Window picker card
    // ─────────────────────────────────────────────────────────────────

    private var windowPickerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader("GAME WINDOW", icon: "macwindow")

            VStack(spacing: 10) {
                fieldRow(icon: "textformat", label: "Window Title") {
                    TextField("e.g. Minecraft", text: $windowTitle)
                        .textFieldStyle(.roundedBorder)
                }

                fieldRow(icon: "app.badge", label: "Bundle ID") {
                    TextField("com.example.game", text: $bundleID)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Spacer()
                    Button {
                        // Placeholder: ScreenCaptureKit refresh
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Refresh")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .neonTile(.cyan, state: .idle, shape: .card)
    }

    @ViewBuilder
    private func fieldRow(
        icon: String,
        label: String,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                .frame(width: 18)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                .frame(width: 80, alignment: .leading)
            trailing()
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Model status card
    // ─────────────────────────────────────────────────────────────────

    private var modelStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader("MODEL", icon: "cpu")

            // Model name row
            HStack(spacing: 10) {
                Image(systemName: "cube.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [VoltPaper.accent, SwooshNeonTokens.Accent.cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("NitroGen 493M")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                    Text("NVIDIA GameNGen · Vision-Action")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                }
                Spacer()
            }

            // Memory row
            HStack(spacing: 8) {
                Image(systemName: "memorychip")
                    .font(.system(size: 12))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                    .frame(width: 18)
                Text("~1.0 GB")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)

                // Mini memory bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(VoltPaper.foreground.opacity(0.06))
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [SwooshNeonTokens.Accent.cyan.opacity(0.6), SwooshNeonTokens.Accent.cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * 0.15)  // ~1GB of typical 8GB budget
                    }
                }
                .frame(width: 60, height: 4)

                Spacer()
            }

            // MPS status
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(VoltPaper.accent)
                    .frame(width: 18)
                Text("MPS Ready")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                Text("Apple Silicon")
                    .font(.system(size: 10))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                Spacer()
            }

            // Download status
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                    .frame(width: 18)
                Text("Ready")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                Spacer()

                Button {
                    // Placeholder: reinstall
                } label: {
                    Text("Reinstall")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .neonTile(.cyan, state: .idle, shape: .card)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Controls card
    // ─────────────────────────────────────────────────────────────────

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader("CONTROLS", icon: "slider.horizontal.3")

            // FPS slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("FPS Target")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                    Spacer()
                    Text("\(Int(fpsTarget))")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                }
                Slider(value: $fpsTarget, in: 10...60, step: 1)
                    .tint(SwooshNeonTokens.Accent.cyan)
            }

            // Mouse sensitivity
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Mouse Sensitivity")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                    Spacer()
                    Text("\(Int(mouseSensitivity))")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                }
                Slider(value: $mouseSensitivity, in: 1...20, step: 1)
                    .tint(SwooshNeonTokens.Accent.cyan)
            }

            // Toggles
            cardDivider

            toggleRow(icon: "keyboard", title: "Use WASD", detail: "Standard FPS movement keys", isOn: $useWASD)
            cardDivider
            toggleRow(icon: "xmark.rectangle", title: "Block Menu Buttons", detail: "Suppress Esc / menu during play", isOn: $blockMenuButtons)
            cardDivider
            toggleRow(icon: "eye", title: "Dry Run", detail: "Capture only — no input injection", isOn: $dryRun)
        }
        .padding(14)
        .neonTile(.cyan, state: .idle, shape: .card)
    }

    @ViewBuilder
    private func toggleRow(icon: String, title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Computed helpers
    // ─────────────────────────────────────────────────────────────────

    private var isCloudSource: Bool {
        guard case .web = selectedSource else { return false }
        return true
    }

    private var isNativeSource: Bool {
        guard case .native = selectedSource else { return false }
        return true
    }

    private var selectedCloudService: CloudGamingService? {
        guard case .web(let svc) = selectedSource else { return nil }
        return svc
    }

    private var selectedNativeSource: NativeGameSource? {
        guard case .native(let src) = selectedSource else { return nil }
        return src
    }

    private func scanForWindows(source: NativeGameSource) {
        isScanning = true
        Task {
            do {
                let windows = try await NativeGameBridge.discoverWindows(for: source)
                await MainActor.run {
                    discoveredWindows = windows.map { (id: UInt32($0.id), title: $0.title, bundleID: $0.bundleID) }
                    selectedWindowID = windows.first.map { UInt32($0.id) }
                    isScanning = false
                }
            } catch {
                await MainActor.run {
                    discoveredWindows = []
                    isScanning = false
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Native setup card
    // ─────────────────────────────────────────────────────────────────

    private var nativeSetupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader("NATIVE SOURCE", icon: "macwindow")

            if let src = selectedNativeSource {
                // Header row
                HStack(spacing: 10) {
                    Image(systemName: src.iconName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(SwooshNeonTokens.Accent.cyan)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(src.displayName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                        Text(src.bundleIdentifiers.first ?? "Any window")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                    }
                    Spacer()

                    // Scan button
                    Button {
                        scanForWindows(source: src)
                    } label: {
                        HStack(spacing: 4) {
                            if isScanning {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            Text("Scan")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                    }
                    .buttonStyle(.plain)
                    .disabled(isScanning)
                }

                cardDivider

                if discoveredWindows.isEmpty {
                    // Not found — show setup instructions
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(VoltPaper.Chart.c4)
                            Text("App not detected")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(VoltPaper.Chart.c4)
                        }

                        Text(src.setupInstructions)
                            .font(.system(size: 11))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                            .lineLimit(6)
                            .fixedSize(horizontal: false, vertical: true)

                        // Quick install buttons
                        if src == .playstation {
                            HStack(spacing: 10) {
                                nativeInstallButton(
                                    title: "Install Chiaki",
                                    icon: "arrow.down.circle",
                                    command: "brew install --cask chiaki"
                                )
                                nativeInstallButton(
                                    title: "PS Remote Play",
                                    icon: "safari",
                                    command: "open https://www.playstation.com/remote-play/"
                                )
                            }
                        } else if src == .steamLink {
                            nativeInstallButton(
                                title: "Mac App Store",
                                icon: "arrow.down.circle",
                                command: "open macappstore://apps.apple.com/app/steam-link/id1246969117"
                            )
                        } else if src == .greenlight {
                            nativeInstallButton(
                                title: "Install Greenlight",
                                icon: "arrow.down.circle",
                                command: "open https://github.com/nicovs/greenlight/releases"
                            )
                        }
                    }
                } else {
                    // Found windows — show picker
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(VoltPaper.accent)
                            Text("\(discoveredWindows.count) window\(discoveredWindows.count == 1 ? "" : "s") detected")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(VoltPaper.accent)
                        }

                        ForEach(discoveredWindows, id: \.id) { window in
                            Button {
                                selectedWindowID = window.id
                                windowTitle = window.title
                                bundleID = window.bundleID
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: selectedWindowID == window.id ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 12))
                                        .foregroundStyle(selectedWindowID == window.id ? SwooshNeonTokens.Accent.cyan : SwooshNeonTokens.Canvas.text3)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(window.title)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                                            .lineLimit(1)
                                        Text(window.bundleID)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                                    }

                                    Spacer()
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(selectedWindowID == window.id
                                            ? SwooshNeonTokens.Accent.cyan.opacity(0.08)
                                            : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(14)
        .neonTile(.cyan, state: !discoveredWindows.isEmpty ? .active : .idle, shape: .card)
    }

    @ViewBuilder
    private func nativeInstallButton(title: String, icon: String, command: String) -> some View {
        Button {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            try? process.run()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(SwooshNeonTokens.Accent.cyan)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(SwooshNeonTokens.Accent.cyan.opacity(0.3), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Cloud info card
    // ─────────────────────────────────────────────────────────────────

    private var cloudInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader("CLOUD SERVICE", icon: "cloud.fill")

            if let svc = selectedCloudService {
                HStack(spacing: 10) {
                    Image(systemName: svc.iconName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color(hex: svc.accentHex))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(svc.displayName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                        Text(svc.streamURL.host ?? svc.streamURL.absoluteString)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                    }
                    Spacer()

                    Circle()
                        .fill(streamStatus == .playing ? VoltPaper.accent : VoltPaper.Chart.c4)
                        .frame(width: 8, height: 8)
                        .shadow(color: streamStatus == .playing ? VoltPaper.accent.opacity(0.6) : .clear, radius: 4)
                }

                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                    Text("Sign into your account in the preview panel. The agent will play through the browser.")
                        .font(.system(size: 10))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                        .lineLimit(3)
                }
            }
        }
        .padding(14)
        .neonTile(.cyan, state: isCloudSource ? .active : .idle, shape: .card)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Stream preview card
    // ─────────────────────────────────────────────────────────────────

    private var streamPreviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                cardHeader("PREVIEW", icon: "tv")
                Spacer()
                if isCloudSource {
                    Text(streamStatus.rawValue.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(streamStatus == .playing ? VoltPaper.accent : SwooshNeonTokens.Canvas.text3)
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(VoltPaper.foreground.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                streamStatus == .playing
                                    ? VoltPaper.accent.opacity(0.3)
                                    : SwooshNeonTokens.Line.rule,
                                lineWidth: streamStatus == .playing ? 1.0 : 0.5
                            )
                    )

                if let bridge = webBridge, let svc = selectedCloudService {
                    WebStreamView(
                        service: svc,
                        bridge: bridge,
                        onStatusChange: { newStatus in
                            streamStatus = newStatus
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        StreamStatusOverlay(
                            status: streamStatus,
                            fps: currentFPS,
                            agentActive: isRunning
                        )
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 36, weight: .ultraLight))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        SwooshNeonTokens.Accent.cyan.opacity(0.4),
                                        SwooshNeonTokens.Accent.cyan.opacity(0.15)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        Text(selectedSource == nil ? "Select a service to begin" : "Preview")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                    }
                }
            }
            .frame(height: 320)
        }
        .padding(14)
        .neonTile(.cyan, state: streamStatus == .playing ? .active : .idle, shape: .card)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Status card
    // ─────────────────────────────────────────────────────────────────

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader("STATUS", icon: "chart.bar")

            // Running indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(isRunning ? VoltPaper.accent : VoltPaper.destructive.opacity(0.6))
                    .frame(width: 8, height: 8)
                    .shadow(
                        color: isRunning ? VoltPaper.accent.opacity(0.7) : .clear,
                        radius: isRunning ? 4 : 0
                    )
                    .scaleEffect(isRunning && pulseAnimation ? 1.3 : 1.0)
                    .animation(
                        isRunning
                            ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                            : .default,
                        value: pulseAnimation
                    )

                Text(isRunning ? "Running" : "Stopped")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isRunning ? VoltPaper.accent : SwooshNeonTokens.Canvas.text2)

                Spacer()
            }
            .onChange(of: isRunning) { _, running in
                pulseAnimation = running
            }

            // Stats grid
            HStack(spacing: 16) {
                statChip(label: "Steps", value: "\(stepCount)", icon: "number")
                statChip(label: "FPS", value: String(format: "%.0f", currentFPS), icon: "speedometer")
            }

            // Window title
            HStack(spacing: 6) {
                Image(systemName: "macwindow")
                    .font(.system(size: 10))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                Text(windowTitle.isEmpty ? "No window selected" : windowTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                    .lineLimit(1)
            }

            cardDivider

            // Recording toggle
            HStack(spacing: 8) {
                Image(systemName: isRecording ? "record.circle.fill" : "record.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isRecording ? VoltPaper.destructive : SwooshNeonTokens.Canvas.text3)
                    .symbolEffect(.pulse, isActive: isRecording)

                Text("Recording")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)

                Spacer()

                Toggle("", isOn: $isRecording)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .neonTile(.cyan, state: isRunning ? .active : .idle, shape: .card)
    }

    @ViewBuilder
    private func statChip(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(VoltPaper.foreground.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(SwooshNeonTokens.Line.rule, lineWidth: 0.5)
                )
        )
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Start / Stop button
    // ─────────────────────────────────────────────────────────────────




    // ─────────────────────────────────────────────────────────────────
    // MARK: - Controller display section
    // ─────────────────────────────────────────────────────────────────

    private var controllerLayout: InteractiveControllerView.Layout {
        if let manual = manualControllerLayout { return manual }
        if case .native(.playstation) = selectedSource { return .playstation }
        return .xbox
    }

    private var controllerBrandColor: Color {
        switch selectedSource {
        case .native(.playstation):
            return Color(hex: "#006FCD")
        case .web(.xboxCloud), .native(.greenlight):
            return Color(hex: "#107C10")
        case .web(.geforceNow):
            return Color(hex: "#76B900")
        default:
            return SwooshNeonTokens.Accent.cyan
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Key mapping modal
    // ─────────────────────────────────────────────────────────────────

    private var keyMappingModalContent: some View {
        VStack(spacing: 0) {
            // Modal header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(controllerBrandColor)
                    Text("Key Mapping")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                }

                Spacer()

                // Controller layout picker
                Menu {
                    Button {
                        manualControllerLayout = .xbox
                    } label: {
                        Label("Xbox Controller", systemImage: "xbox.logo")
                    }
                    Button {
                        manualControllerLayout = .playstation
                    } label: {
                        Label("DualSense (PS5)", systemImage: "playstation.logo")
                    }
                    Divider()
                    Button {
                        manualControllerLayout = nil
                    } label: {
                        Label("Auto (match platform)", systemImage: "arrow.triangle.2.circlepath")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: controllerLayout == .playstation ? "playstation.logo" : "xbox.logo")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(controllerBrandColor)
                        Text(controllerLayout == .playstation ? "DualSense" : "Xbox")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(VoltPaper.foreground.opacity(0.06))
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button {
                    showKeyMappingModal = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider().opacity(0.2)

            // Table header
            HStack {
                Text("Controller Button")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("macOS Key")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider().opacity(0.1)

            // Rows
            ScrollView {
                VStack(spacing: 0) {
                    ForEach($keyMappings) { $mapping in
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: mapping.icon)
                                    .font(.system(size: 12))
                                    .foregroundStyle(controllerBrandColor)
                                    .frame(width: 18)
                                Text(mapping.xboxButton)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            TextField("Key", text: $mapping.macKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13, design: .monospaced))
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 7)

                        Divider().opacity(0.05).padding(.horizontal, 20)
                    }
                }
            }

            Divider().opacity(0.2)

            // FPS + Sensitivity controls
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "speedometer")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(controllerBrandColor)
                        .frame(width: 16)
                    Text("FPS Target")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                    Spacer()
                    Text("\(Int(fpsTarget))")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(controllerBrandColor)
                }
                Slider(value: $fpsTarget, in: 10...60, step: 1)
                    .tint(controllerBrandColor)

                HStack {
                    Image(systemName: "computermouse")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(controllerBrandColor)
                        .frame(width: 16)
                    Text("Mouse Sensitivity")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                    Spacer()
                    Text("\(Int(mouseSensitivity))")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(controllerBrandColor)
                }
                Slider(value: $mouseSensitivity, in: 1...20, step: 1)
                    .tint(controllerBrandColor)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider().opacity(0.2)

            // Footer actions
            HStack(spacing: 12) {
                Spacer()

                Button {
                    // Load from file
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc")
                            .font(.system(size: 12))
                        Text("Load from File")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                }
                .buttonStyle(.plain)

                Button {
                    keyMappings = KeyMapping.defaults
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12))
                        Text("Reset to Default")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(controllerBrandColor)
                }
                .buttonStyle(.plain)

                Button {
                    showKeyMappingModal = false
                } label: {
                    Text("Done")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(VoltPaper.foreground)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(controllerBrandColor))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .frame(width: 520, height: 680)
        .background(SwooshNeonTokens.Canvas.bg)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Shared helpers
    // ─────────────────────────────────────────────────────────────────

    @ViewBuilder
    private func cardHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SwooshNeonTokens.Accent.cyan)
            Text(title)
                .font(.system(size: 9.5, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
        }
    }

    private var cardDivider: some View {
        Rectangle()
            .fill(SwooshNeonTokens.Line.rule)
            .frame(height: 0.5)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Gaming send handler wiring
    // ─────────────────────────────────────────────────────────────────

    private func wireGamingSendHandler() {
        voiceMode.shell.send = makeGamingSendHandler(
            contextProvider: { [self] in
                GamingContext(
                    selectedPlatform: selectedSource?.displayName,
                    streamStatus: streamStatus,
                    isNitroGenRunning: isRunning,
                    currentFPS: currentFPS,
                    stepCount: stepCount,
                    windowTitle: windowTitle.isEmpty ? nil : windowTitle,
                    bundleID: bundleID.isEmpty ? nil : bundleID,
                    availableKeymaps: discoverAvailableKeymaps()
                )
            }
        )
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Navigation tool notification handlers
    // ─────────────────────────────────────────────────────────────────

    private func handleSearchGame(_ note: Notification) {
        guard let query = note.userInfo?["query"] as? String,
              let bridge = webBridge else { return }
        Task {
            // Type into the service's search box and press Enter
            let js = """
            (function() {
                var search = document.querySelector('input[type="search"], input[type="text"], [role="searchbox"], input[placeholder*="earch"]');
                if (!search) return 'no_search_field';
                search.focus();
                search.value = '\(query.replacingOccurrences(of: "'", with: "\\'"))';
                search.dispatchEvent(new Event('input', {bubbles: true}));
                search.dispatchEvent(new KeyboardEvent('keydown', {key:'Enter', code:'Enter', bubbles:true}));
                search.dispatchEvent(new KeyboardEvent('keyup', {key:'Enter', code:'Enter', bubbles:true}));
                return 'ok';
            })();
            """
            _ = try? await bridge.webView?.evaluateJavaScript(js)
        }
    }

    private func handleClickElement(_ note: Notification) {
        guard let selector = note.userInfo?["selector"] as? String,
              let bridge = webBridge else { return }
        Task {
            let js = """
            (function() {
                var el = document.querySelector('\(selector.replacingOccurrences(of: "'", with: "\\'"))');
                if (!el) return 'not_found';
                el.click();
                return 'clicked';
            })();
            """
            _ = try? await bridge.webView?.evaluateJavaScript(js)
        }
    }

    private func handleTypeText(_ note: Notification) {
        guard let text = note.userInfo?["text"] as? String,
              let bridge = webBridge else { return }
        Task {
            let js = """
            (function() {
                var el = document.activeElement;
                if (!el) return 'no_focus';
                el.value = '\(text.replacingOccurrences(of: "'", with: "\\'"))';
                el.dispatchEvent(new Event('input', {bubbles: true}));
                return 'typed';
            })();
            """
            _ = try? await bridge.webView?.evaluateJavaScript(js)
        }
    }

    private func handleNavigateURL(_ note: Notification) {
        guard let urlString = note.userInfo?["url"] as? String,
              let url = URL(string: urlString),
              let bridge = webBridge else { return }
        Task {
            bridge.webView?.load(URLRequest(url: url))
        }
    }

    private func handleSelectPlatform(_ note: Notification) {
        guard let platform = note.userInfo?["platform"] as? String else { return }
        let mapped: GameSource? = switch platform.lowercased() {
        case "xbox", "xboxcloud":    .web(.xboxCloud)
        case "geforce", "geforcenow": .web(.geforceNow)
        case "luna", "amazonluna":    .web(.amazonLuna)
        case "boosteroid":            .web(.boosteroid)
        case "steamlink", "steam":    .native(.steamLink)
        case "playstation", "ps":     .native(.playstation)
        case "greenlight":            .native(.greenlight)
        case "local", "window":       .native(.localWindow)
        default: nil
        }
        if let mapped {
            selectedSource = mapped
        }
    }
}


// ═══════════════════════════════════════════════════════════════════
// MARK: - Key mapping model
// ═══════════════════════════════════════════════════════════════════

struct KeyMapping: Identifiable {
    let id: String
    let xboxButton: String
    let icon: String
    var macKey: String

    static let defaults: [KeyMapping] = [
        KeyMapping(id: "a", xboxButton: "A", icon: "a.circle", macKey: "Space"),
        KeyMapping(id: "b", xboxButton: "B", icon: "b.circle", macKey: "E"),
        KeyMapping(id: "x", xboxButton: "X", icon: "x.circle", macKey: "R"),
        KeyMapping(id: "y", xboxButton: "Y", icon: "y.circle", macKey: "Q"),
        KeyMapping(id: "lb", xboxButton: "LB", icon: "l.joystick.tilt.left", macKey: "Tab"),
        KeyMapping(id: "rb", xboxButton: "RB", icon: "r.joystick.tilt.right", macKey: "F"),
        KeyMapping(id: "lt", xboxButton: "LT", icon: "l2.button.roundedtop.horizontal", macKey: "RightClick"),
        KeyMapping(id: "rt", xboxButton: "RT", icon: "r2.button.roundedtop.horizontal", macKey: "LeftClick"),
        KeyMapping(id: "lstick", xboxButton: "L-Stick", icon: "l.joystick", macKey: "WASD"),
        KeyMapping(id: "rstick", xboxButton: "R-Stick", icon: "r.joystick", macKey: "Mouse"),
        KeyMapping(id: "dpad_up", xboxButton: "D-Pad Up", icon: "dpad.up.filled", macKey: "↑"),
        KeyMapping(id: "dpad_down", xboxButton: "D-Pad Down", icon: "dpad.down.filled", macKey: "↓"),
        KeyMapping(id: "dpad_left", xboxButton: "D-Pad Left", icon: "dpad.left.filled", macKey: "←"),
        KeyMapping(id: "dpad_right", xboxButton: "D-Pad Right", icon: "dpad.right.filled", macKey: "→"),
    ]
}

#endif
