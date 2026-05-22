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

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                brainSection
                listenSection
                speakSection
                musicSection
            }
            .navigationTitle("Agent")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                #else
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                #endif
            }
        }
    }

    // MARK: - Brain

    /// Grouped (providerID, models) pairs preserving the catalog's order
    /// so cloud and local runtimes each show up under their own header
    /// instead of a single flat list.
    private var modelsByProvider: [(providerID: String, models: [UnifiedModelEntry])] {
        var seen: [String] = []
        var grouped: [String: [UnifiedModelEntry]] = [:]
        for entry in models {
            if grouped[entry.providerID] == nil { seen.append(entry.providerID) }
            grouped[entry.providerID, default: []].append(entry)
        }
        return seen.map { ($0, grouped[$0] ?? []) }
    }

    @ViewBuilder
    private var brainSection: some View {
        Section {
            if currentSupportsEffort {
                Picker("Intelligence", selection: $effort) {
                    ForEach(ReasoningEffort.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
            }
        } header: {
            Label("Brain", systemImage: "brain")
        } footer: {
            Text("The model that interprets every message and decides which tools to run.")
        }

        ForEach(modelsByProvider, id: \.providerID) { group in
            Section {
                ForEach(group.models) { entry in
                    Button {
                        selectedModelID = entry.id
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.displayName)
                                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                                Text(entry.blurb)
                                    .font(.caption)
                                    .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                            }
                            Spacer()
                            if entry.id == selectedModelID {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(UnifiedModelCatalog.providerDisplayName(group.providerID))
            }
        }
    }

    // MARK: - Listen (STT)

    @ViewBuilder
    private var listenSection: some View {
        Section {
            Picker("Engine", selection: $sttEngineRaw) {
                Text("Apple Speech").tag("system")
                Text("Whisper (on-device)").tag("whisper")
            }
        } header: {
            Label("Listen", systemImage: "ear")
        } footer: {
            Text("Converts your voice into text. Both run on-device.")
        }
    }

    // MARK: - Speak (TTS)

    @ViewBuilder
    private var speakSection: some View {
        Section {
            Picker("Engine", selection: $ttsEngineRaw) {
                Text("Apple voices").tag("system")
                Text("ElevenLabs").tag("elevenlabs")
                Text("OpenAI TTS").tag("openai-tts")
                Text("Cartesia Sonic").tag("cartesia")
            }
        } header: {
            Label("Speak", systemImage: "waveform")
        } footer: {
            Text("Reads agent replies aloud. Cloud engines need an API key in Settings → Voice.")
        }
    }

    // MARK: - Music

    @ViewBuilder
    private var musicSection: some View {
        Section {
            Picker("Provider", selection: $musicProviderRaw) {
                Text("Suno").tag("suno")
                Text("ElevenLabs Music").tag("elevenlabs-music")
                Text("Stable Audio").tag("stable-audio")
            }
        } header: {
            Label("Music", systemImage: "music.note")
        } footer: {
            Text("Used when the agent generates music. All providers require an API key.")
        }
    }

    // MARK: - Derived

    private var currentSupportsEffort: Bool {
        models.first(where: { $0.id == selectedModelID })?.supportsReasoningEffort ?? false
    }
}
