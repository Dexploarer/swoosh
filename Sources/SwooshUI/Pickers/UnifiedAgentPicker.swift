// SwooshUI/Pickers/UnifiedAgentPicker.swift — Brain · Listen · Speak · Music
//
// A single compact glyph in the chat header that opens a configuration sheet
// for every modality the agent uses:
//   • Brain   — model + reasoning effort
//   • Listen  — STT engine (Apple Speech vs Whisper on-device)
//   • Speak   — TTS engine (Apple, ElevenLabs, OpenAI, Cartesia)
//   • Music   — music-gen provider (Suno, ElevenLabs Music, Stable Audio)
//
// The sheet is styled in the **Volt Paper** system (see VoltPaper.swift):
// obsidian canvas, inky type, electric-violet for selections, acid-lime only
// for live signal, flat bordered rows — no gradients, no stock gray Pickers.
// Selections persist through `@AppStorage` keys matching VoltRouter's
// UserDefaults keys, so flipping a row changes what the router returns on the
// next call.

import SwiftUI
import SwooshGenerativeUI
import SwooshModels
import SwooshProviders

// ═══════════════════════════════════════════════════════════════════
// MARK: - Trigger (lives in the neon chat input row — left as-is)
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
// MARK: - Sheet (Volt Paper)
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

    // ── Derived (unchanged) ──

    private var selectedModels: [UnifiedModelEntry] {
        var result: [UnifiedModelEntry] = []
        if let brain = models.first(where: { $0.id == selectedModelID }) { result.append(brain) }
        if let stt = localMLXModels.first(where: { $0.id.contains(sttEngineRaw) }) { result.append(stt) }
        if let tts = localMLXModels.first(where: { $0.id.contains(ttsEngineRaw) }) { result.append(tts) }
        return result
    }

    private var localMLXModels: [UnifiedModelEntry] {
        models.filter { $0.runtime == .localMLX || $0.runtime == .localOpenAI || $0.runtime == .localLiteRT || $0.runtime == .localFoundation }
    }

    private var cloudModels: [UnifiedModelEntry] {
        models.filter { $0.runtime == .openAI || $0.runtime == .openRouter || $0.runtime == .detourCloud || $0.runtime == .router || $0.runtime == .codex }
    }

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

    private var cloudModelsByProvider: [(providerID: String, models: [UnifiedModelEntry])] {
        var seen: [String] = []
        var grouped: [String: [UnifiedModelEntry]] = [:]
        for entry in cloudModels {
            if grouped[entry.providerID] == nil { seen.append(entry.providerID) }
            grouped[entry.providerID, default: []].append(entry)
        }
        return seen.map { ($0, grouped[$0] ?? []) }
    }

    // ── Body ──

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    MemoryBudgetView(hardware: hardware, selectedModels: selectedModels)
                    brainSection
                    if !localSpecialtyModels.isEmpty { specialtySection }
                    listenSpeakMusicSection
                }
                .padding(20)
            }
        }
        .frame(width: 680, height: 720)
        .background(VoltPaper.background)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                VoltSectionLabel("Agent / Config")
                Text("Models & voices")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(VoltPaper.foreground)
            }
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.voltPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) {
            Rectangle().fill(VoltPaper.border).frame(height: 1)
        }
    }

    // ── Brain ──

    private var brainSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VoltSectionLabel("Brain")

            if currentSupportsEffort {
                HStack(spacing: 14) {
                    Text("Reasoning effort")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(VoltPaper.foreground)
                    Spacer()
                    VoltSegmented(
                        ReasoningEffort.allCases.map { .init($0.displayName, $0) },
                        selection: $effort
                    )
                    .frame(width: 260)
                }
            }

            searchField

            VStack(alignment: .leading, spacing: 6) {
                ForEach(localBrainFamilies, id: \.family) { group in
                    familyHeader(group.family, count: group.models.count)
                    ForEach(group.models) { entry in modelRow(entry: entry) }
                }
            }

            if !cloudModels.isEmpty { cloudDisclosure }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(VoltPaper.mutedFg)
            TextField("Search models…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(VoltPaper.foreground)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: VoltPaper.Radius.md, style: .continuous).fill(VoltPaper.background))
        .overlay(RoundedRectangle(cornerRadius: VoltPaper.Radius.md, style: .continuous).strokeBorder(VoltPaper.border, lineWidth: 1))
    }

    private var cloudDisclosure: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showCloudModels.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showCloudModels ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                    VoltSectionLabel("Cloud Providers")
                    Text("(\(cloudModels.count))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(VoltPaper.mutedFg)
                    Spacer()
                    Text("no memory impact")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(VoltPaper.mutedFg)
                }
                .foregroundStyle(VoltPaper.mutedFg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showCloudModels {
                ForEach(cloudModelsByProvider, id: \.providerID) { group in
                    providerSubheader(group.providerID)
                    ForEach(group.models) { entry in modelRow(entry: entry, cloud: true) }
                }
            }
        }
        .padding(.top, 6)
    }

    // ── Specialty ──

    private var specialtySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VoltSectionLabel("Specialty Models")
            VStack(spacing: 8) {
                ForEach(localSpecialtyModels) { entry in specialtyRow(entry: entry) }
            }
        }
    }

    // ── Listen / Speak / Music ──

    private var listenSpeakMusicSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            providerRow(
                label: "Listen", caption: "Speech-to-text",
                options: [.init("Apple Speech", "system"), .init("Whisper", "whisper")],
                selection: $sttEngineRaw
            )
            providerRow(
                label: "Speak", caption: "Text-to-speech",
                options: [.init("Apple", "system"), .init("ElevenLabs", "elevenlabs"),
                          .init("OpenAI", "openai-tts"), .init("Cartesia", "cartesia")],
                selection: $ttsEngineRaw
            )
            providerRow(
                label: "Music", caption: "Generation provider",
                options: [.init("Suno", "suno"), .init("ElevenLabs", "elevenlabs-music"),
                          .init("Stable Audio", "stable-audio")],
                selection: $musicProviderRaw
            )
        }
    }

    private func providerRow(
        label: String, caption: String,
        options: [VoltSegmented<String>.Option], selection: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VoltSectionLabel(label)
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(VoltPaper.mutedFg)
            }
            VoltSegmented(options, selection: selection)
        }
        .voltCard(padding: 16)
    }

    // ── Rows ──

    private func familyHeader(_ family: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(family.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1)
            Text("(\(count))").font(.system(size: 10, design: .monospaced))
        }
        .foregroundStyle(VoltPaper.mutedFg)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func modelRow(entry: UnifiedModelEntry, cloud: Bool = false) -> some View {
        let selected = entry.id == selectedModelID
        let memGB = entry.estimatedMemoryGB ?? 0
        let fits = cloud || memGB <= usableMemory
        Button {
            selectedModelID = entry.id
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(entry.displayName)
                            .font(.system(size: 13, weight: selected ? .bold : .medium))
                            .foregroundStyle(fits ? VoltPaper.foreground : VoltPaper.destructive)
                        if !fits {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9)).foregroundStyle(VoltPaper.destructive)
                        }
                    }
                    Text(entry.blurb)
                        .font(.system(size: 11)).foregroundStyle(VoltPaper.mutedFg).lineLimit(1)
                }
                Spacer()
                if cloud {
                    Image(systemName: "cloud").font(.system(size: 11)).foregroundStyle(VoltPaper.mutedFg)
                } else if memGB > 0 {
                    ModelMemoryBar(memoryGB: memGB, maxMemoryGB: usableMemory)
                }
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15)).foregroundStyle(VoltPaper.primary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: VoltPaper.Radius.md, style: .continuous)
                    .fill(selected ? VoltPaper.primary.opacity(0.14) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: VoltPaper.Radius.md, style: .continuous)
                    .strokeBorder(selected ? VoltPaper.primary.opacity(0.5) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func specialtyRow(entry: UnifiedModelEntry) -> some View {
        let memGB = entry.estimatedMemoryGB ?? 0
        return HStack(spacing: 12) {
            Image(systemName: specialtyIcon(for: entry))
                .font(.system(size: 13)).foregroundStyle(VoltPaper.primary).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(VoltPaper.foreground)
                Text(entry.blurb)
                    .font(.system(size: 10.5)).foregroundStyle(VoltPaper.mutedFg).lineLimit(1)
            }
            Spacer()
            if memGB > 0 { ModelMemoryBar(memoryGB: memGB, maxMemoryGB: usableMemory) }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .voltCard(VoltPaper.Radius.md, padding: 0)
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

    private func providerSubheader(_ providerID: String) -> some View {
        Text(UnifiedModelCatalog.providerDisplayName(providerID).uppercased())
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .tracking(1)
            .foregroundStyle(VoltPaper.mutedFg)
            .padding(.top, 6)
    }
}
