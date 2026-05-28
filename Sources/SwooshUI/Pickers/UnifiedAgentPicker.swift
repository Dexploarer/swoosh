// SwooshUI/Pickers/UnifiedAgentPicker.swift — Brain · Listen · Speak · Music
//
// A single compact glyph in the chat header that opens a full-screen
// configuration sheet for every modality the agent uses:
//   • Brain   — model + reasoning effort (was ModelPicker)
//   • Listen  — STT engine (Apple Speech vs Whisper on-device)
//   • Speak   — TTS engine (Apple, ElevenLabs, OpenAI, Cartesia)
//   • Music   — music-gen provider (Suno, ElevenLabs Music, Stable Audio)
//
// Why a sheet instead of a Menu: on a 6.7" iPhone the input row is tight,
// and the SOTA pattern for mobile assistants routes multi-section
// configuration into a bottom sheet so the composer stays minimal. The
// trigger is a single SF Symbol — no model name, no effort glyph, no
// reflow when the chosen model has a long name. Bottom-sheet selections
// persist through `@AppStorage` keys that match VoiceRouter's UserDefaults
// keys exactly, so flipping a row here changes what the router returns
// from `activeCloudTTSProvider()` / `activeSTTProvider()` /
// `activeMusicProvider()` on the very next call.

import SwiftUI
import SwooshGenerativeUI
import SwooshModels
import SwooshProviders

// ═══════════════════════════════════════════════════════════════════
// MARK: - Trigger
// ═══════════════════════════════════════════════════════════════════

public struct UnifiedAgentPicker: View {

    public let models: [UnifiedModelEntry]
    @Binding public var selectedModelID: String
    @Binding public var effort: ReasoningEffort
    public let accent: NeonAccent

    @State private var isPresented = false

    public init(
        models: [UnifiedModelEntry],
        selectedModelID: Binding<String>,
        effort: Binding<ReasoningEffort>,
        accent: NeonAccent = .cyan
    ) {
        self.models = models
        self._selectedModelID = selectedModelID
        self._effort = effort
        self.accent = accent
    }

    public var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                .frame(width: 36, height: 36)
                .neonTile(accent, state: .idle, shape: .card)
        }
        .buttonStyle(.plain)
        .help("Brain · Listen · Speak · Music")
        .accessibilityLabel("Agent configuration")
        .sheet(isPresented: $isPresented) {
            UnifiedAgentSheet(
                models: models,
                selectedModelID: $selectedModelID,
                effort: $effort
            )
            #if os(iOS)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Sheet body
// ═══════════════════════════════════════════════════════════════════

private struct UnifiedAgentSheet: View {

    let models: [UnifiedModelEntry]
    @Binding var selectedModelID: String
    @Binding var effort: ReasoningEffort

    @AppStorage("swoosh.voice.sttEngine")     private var sttEngineRaw: String = "system"
    @AppStorage("swoosh.voice.ttsEngine")     private var ttsEngineRaw: String = "system"
    @AppStorage("swoosh.voice.musicProvider") private var musicProviderRaw: String = "suno"

    @State private var hardware = HardwareProfile.detectCurrent()
    @State private var searchText = ""
    @State private var showCloudModels = false

    @Environment(\.dismiss) private var dismiss

    // ── Derived ──

    /// Models the user has selected across all slots (brain + stt + tts).
    /// Used to compute total memory budget in the hardware banner.
    private var selectedModels: [UnifiedModelEntry] {
        var result: [UnifiedModelEntry] = []
        if let brain = models.first(where: { $0.id == selectedModelID }) {
            result.append(brain)
        }
        // Add STT/TTS local models if any match
        if let stt = localMLXModels.first(where: { $0.id.contains(sttEngineRaw) }) {
            result.append(stt)
        }
        if let tts = localMLXModels.first(where: { $0.id.contains(ttsEngineRaw) }) {
            result.append(tts)
        }
        return result
    }

    private var localMLXModels: [UnifiedModelEntry] {
        models.filter { $0.runtime == .localMLX || $0.runtime == .localOpenAI || $0.runtime == .localLiteRT || $0.runtime == .localFoundation }
    }

    private var cloudModels: [UnifiedModelEntry] {
        models.filter { $0.runtime == .openAI || $0.runtime == .openRouter || $0.runtime == .detourCloud || $0.runtime == .router || $0.runtime == .codex }
    }

    /// Brain-eligible local models, grouped by family.
    private var localBrainFamilies: [(family: String, models: [UnifiedModelEntry])] {
        let brain = localMLXModels.filter { entry in
            entry.capabilities.contains(.textGeneration)
            && (entry.roles.contains(.agent) || entry.roles.contains(.coder) || entry.roles.contains(.vision))
        }
        let filtered = searchText.isEmpty ? brain : brain.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
            || $0.family.localizedCaseInsensitiveContains(searchText)
        }
        var seen: [String] = []
        var grouped: [String: [UnifiedModelEntry]] = [:]
        for entry in filtered {
            if grouped[entry.family] == nil { seen.append(entry.family) }
            grouped[entry.family, default: []].append(entry)
        }
        return seen.map { ($0, grouped[$0] ?? []) }
    }

    /// Specialty local models (STT, TTS, image gen, embeddings, rerankers, vision-only).
    private var localSpecialtyModels: [UnifiedModelEntry] {
        localMLXModels.filter { entry in
            !entry.capabilities.contains(.textGeneration)
            || (!entry.roles.contains(.agent) && !entry.roles.contains(.coder))
        }
    }

    private var usableMemory: Double { hardware.usableMemoryGB }

    private var currentSupportsEffort: Bool {
        models.first(where: { $0.id == selectedModelID })?.supportsReasoningEffort ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──
            HStack {
                Text("AGENT CONFIG")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                Spacer()
                Button { dismiss() } label: {
                    Text("Done")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            // ── Hardware banner ──
            MemoryBudgetView(hardware: hardware, selectedModels: selectedModels)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            Rectangle()
                .fill(SwooshNeonTokens.Line.rule)
                .frame(height: 0.5)

            // ── Content ──
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    // ── Brain: Intelligence ──
                    sectionHeader("Brain", icon: "brain")

                    if currentSupportsEffort {
                        HStack(spacing: 12) {
                            Text("Intelligence")
                                .font(.system(size: 13))
                                .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                            Spacer()
                            Picker("", selection: $effort) {
                                ForEach(ReasoningEffort.allCases, id: \.self) { level in
                                    Text(level.displayName).tag(level)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 220)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }

                    // ── Search bar ──
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                        TextField("Search models…", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)

                    // ── Local MLX Models (Brain) ──
                    ForEach(localBrainFamilies, id: \.family) { group in
                        familyHeader(group.family, count: group.models.count)
                        ForEach(group.models) { entry in
                            modelRow(entry: entry)
                        }
                    }

                    // ── Cloud toggle ──
                    if !cloudModels.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showCloudModels.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: showCloudModels ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                Text("CLOUD PROVIDERS")
                                    .font(.system(size: 9, weight: .semibold))
                                    .tracking(1.5)
                                Text("(\(cloudModels.count))")
                                    .font(.system(size: 9))
                                Spacer()
                                Text("No memory impact")
                                    .font(.system(size: 9))
                                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                            }
                            .foregroundStyle(SwooshNeonTokens.Accent.cyan.opacity(0.6))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 12)

                        if showCloudModels {
                            ForEach(cloudModelsByProvider, id: \.providerID) { group in
                                providerSubheader(group.providerID)
                                ForEach(group.models) { entry in
                                    cloudModelRow(entry: entry)
                                }
                            }
                        }
                    }

                    // ── Specialty local models ──
                    if !localSpecialtyModels.isEmpty {
                        sectionHeader("Specialty Models", icon: "sparkles")
                            .padding(.top, 16)

                        ForEach(localSpecialtyModels) { entry in
                            specialtyRow(entry: entry)
                        }
                    }

                    // ── Listen / Speak / Music ──
                    sectionHeader("Listen", icon: "ear")
                        .padding(.top, 16)

                    HStack(spacing: 14) {
                        SwooshOrbView(configuration: SwooshOrbConfiguration(
                            backgroundColors: [.cyan, .green, .teal],
                            glowColor: .cyan,
                            coreGlowIntensity: 0.7,
                            showParticles: false, showShadow: false, speed: 35
                        ))
                        .frame(width: 32, height: 32)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Speech-to-Text")
                                .font(.system(size: 11))
                                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                            Picker("", selection: $sttEngineRaw) {
                                Text("Apple Speech").tag("system")
                                Text("Whisper (on-device)").tag("whisper")
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                    sectionHeader("Speak", icon: "waveform")
                        .padding(.top, 12)

                    HStack(spacing: 14) {
                        SwooshOrbView(configuration: SwooshOrbConfiguration(
                            backgroundColors: [.purple, .indigo, .cyan],
                            glowColor: .purple,
                            coreGlowIntensity: 0.7,
                            showParticles: false, showShadow: false, speed: 30
                        ))
                        .frame(width: 32, height: 32)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Text-to-Speech")
                                .font(.system(size: 11))
                                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                            Picker("", selection: $ttsEngineRaw) {
                                Text("Apple").tag("system")
                                Text("ElevenLabs").tag("elevenlabs")
                                Text("OpenAI").tag("openai-tts")
                                Text("Cartesia").tag("cartesia")
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                    sectionHeader("Music", icon: "music.note")
                        .padding(.top, 12)

                    HStack(spacing: 12) {
                        Text("Provider")
                            .font(.system(size: 13))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                        Spacer()
                        Picker("", selection: $musicProviderRaw) {
                            Text("Suno").tag("suno")
                            Text("ElevenLabs").tag("elevenlabs-music")
                            Text("Stable Audio").tag("stable-audio")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .padding(16)
            }
        }
        .frame(width: 680, height: 720)
        .background(SwooshNeonTokens.Canvas.bg)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.5)
        }
        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func familyHeader(_ family: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Text(family.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(1)
            Text("(\(count))")
                .font(.system(size: 9))
        }
        .foregroundStyle(SwooshNeonTokens.Accent.cyan.opacity(0.5))
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func modelRow(entry: UnifiedModelEntry) -> some View {
        let selected = entry.id == selectedModelID
        let memGB = entry.estimatedMemoryGB ?? 0
        let fits = memGB <= usableMemory

        Button {
            selectedModelID = entry.id
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(entry.displayName)
                            .font(.system(size: 13, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? SwooshNeonTokens.Canvas.text1 : (fits ? SwooshNeonTokens.Canvas.text2 : .red.opacity(0.7)))
                        if !fits {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.red.opacity(0.7))
                        }
                    }
                    Text(entry.blurb)
                        .font(.system(size: 10))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                        .lineLimit(1)
                }

                Spacer()

                if memGB > 0 {
                    ModelMemoryBar(memoryGB: memGB, maxMemoryGB: usableMemory)
                }

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? SwooshNeonTokens.Accent.cyan.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func cloudModelRow(entry: UnifiedModelEntry) -> some View {
        let selected = entry.id == selectedModelID
        Button {
            selectedModelID = entry.id
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? SwooshNeonTokens.Canvas.text1 : SwooshNeonTokens.Canvas.text2)
                    Text(entry.blurb)
                        .font(.system(size: 10))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "cloud")
                    .font(.system(size: 10))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func specialtyRow(entry: UnifiedModelEntry) -> some View {
        let memGB = entry.estimatedMemoryGB ?? 0
        HStack(spacing: 10) {
            let icon = specialtyIcon(for: entry)
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(SwooshNeonTokens.Accent.cyan.opacity(0.7))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                Text(entry.blurb)
                    .font(.system(size: 10))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                    .lineLimit(1)
            }
            Spacer()
            if memGB > 0 {
                ModelMemoryBar(memoryGB: memGB, maxMemoryGB: usableMemory)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private func specialtyIcon(for entry: UnifiedModelEntry) -> String {
        if entry.capabilities.contains(.speechToText) { return "ear" }
        if entry.capabilities.contains(.textToSpeech) { return "waveform" }
        if entry.capabilities.contains(.imageGeneration) { return "photo.artframe" }
        if entry.capabilities.contains(.embedding) { return "arrow.triangle.branch" }
        if entry.capabilities.contains(.reranking) { return "arrow.up.arrow.down" }
        if entry.capabilities.contains(.vision) { return "eye" }
        return "cube"
    }

    @ViewBuilder
    private func providerSubheader(_ providerID: String) -> some View {
        Text(UnifiedModelCatalog.providerDisplayName(providerID).uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(1)
            .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private var cloudModelsByProvider: [(providerID: String, models: [UnifiedModelEntry])] {
        var seen: [String] = []
        var grouped: [String: [UnifiedModelEntry]] = [:]
        for entry in cloudModels {
            if grouped[entry.providerID] == nil { seen.append(entry.providerID) }
            grouped[entry.providerID, default: []].append(entry)
        }
        return seen.map { ($0, grouped[$0] ?? []) }
    }
}


