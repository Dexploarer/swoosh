// Apps/SwooshiOS/VoicePickerScreen.swift — Unified Settings → Voice
//
// One screen, four sections:
//   1. Speech recognition — engine picker + WhisperKit download manager
//   2. Spoken replies     — TTS provider picker + voice selector + sample button
//   3. Music generation   — provider picker
//   4. Provider keys      — per-service Keychain entry rows
//
// All state lives in UserDefaults (selections) + Keychain (secrets).
// The VoiceRouter reads from both, so flipping a picker is the only
// thing the rest of the app needs to know about.

import SwiftUI
import AVFoundation
import SwooshSTT
import SwooshVoiceProviders
import SwooshMusic

struct VoicePickerScreen: View {

    @AppStorage("swoosh.voice.sttEngine") private var sttEngine: String = "system"
    @AppStorage("swoosh.voice.whisperModel") private var whisperModel: String = "openai_whisper-small"
    @AppStorage("swoosh.voice.ttsEngine") private var ttsEngine: String = "system"
    @AppStorage("swoosh.voice.systemVoiceID") private var systemVoiceID: String = ""
    @AppStorage("swoosh.voice.musicProvider") private var musicProvider: String = "suno"
    @AppStorage("swoosh.voice.cloudVoiceID") private var cloudVoiceID: String = ""

    @State private var whisperManager = WhisperModelManager()
    @State private var sampleStatus: String = ""
    @State private var playback = TTSPlayback()
    @State private var streamingPlayer = StreamingTTSPlayer()
    @AppStorage("swoosh.voice.useStreaming") private var useStreaming: Bool = true

    @State private var cartesiaVoices: [TTSVoice] = []
    @State private var cartesiaSearch: String = ""
    @State private var cartesiaLoadError: String?

    var body: some View {
        List {
            sttSection
            whisperDownloadsSection
            ttsSection
            cartesiaVoiceSection
            musicSection
            cloudKeysSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Voice")
    }

    // MARK: - STT

    private var sttSection: some View {
        Section {
            Picker("Engine", selection: $sttEngine) {
                Text("Apple Dictation").tag("system")
                Text("Whisper (on-device)").tag("whisper")
            }
            if sttEngine == "whisper" {
                Picker("Whisper model", selection: $whisperModel) {
                    ForEach(WhisperModel.allCases, id: \.rawValue) { m in
                        Text(m.displayName).tag(m.rawValue)
                    }
                }
            }
        } header: {
            Text("Speech recognition")
        } footer: {
            Text(sttEngine == "system"
                 ? "Apple's built-in dictation. Free, instant, ~50 languages."
                 : "On-device Core ML; ~40 MB to 800 MB depending on model.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Whisper downloads

    @ViewBuilder
    private var whisperDownloadsSection: some View {
        if sttEngine == "whisper" {
            Section("Whisper models") {
                ForEach(WhisperModel.allCases, id: \.rawValue) { model in
                    whisperRow(model)
                }
            }
        }
    }

    private func whisperRow(_ model: WhisperModel) -> some View {
        let state = whisperManager.state(of: model)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.system(size: 14, weight: .medium))
                Text("\(model.estimatedSizeMB) MB · \(stateLabel(state))")
                    .font(.caption)
                    .foregroundStyle(stateColor(state))
            }
            Spacer()
            actionView(for: model, state: state)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func actionView(for model: WhisperModel, state: WhisperModelManager.DownloadState) -> some View {
        switch state {
        case .notDownloaded:
            Button("Download") { whisperManager.download(model) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        case .downloading(let progress):
            ProgressView(value: progress)
                .frame(width: 60)
        case .ready:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Delete", role: .destructive) { whisperManager.delete(model) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        case .failed:
            Button("Retry") { whisperManager.download(model) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
        }
    }

    private func stateLabel(_ s: WhisperModelManager.DownloadState) -> String {
        switch s {
        case .notDownloaded:        return "Not downloaded"
        case .downloading(let p):   return "Downloading… \(Int(p*100))%"
        case .ready:                return "Ready"
        case .failed(let m):        return "Failed — \(m.prefix(40))"
        }
    }

    private func stateColor(_ s: WhisperModelManager.DownloadState) -> Color {
        switch s {
        case .notDownloaded: return .secondary
        case .downloading:   return .blue
        case .ready:         return .green
        case .failed:        return .red
        }
    }

    // MARK: - TTS

    private var ttsSection: some View {
        Section {
            Picker("Voice", selection: $ttsEngine) {
                Text("Apple voices (system)").tag("system")
                Text("ElevenLabs").tag("elevenlabs")
                Text("OpenAI TTS").tag("openai-tts")
                Text("Cartesia Sonic").tag("cartesia")
            }
            if ttsEngine == "system" {
                Picker("System voice", selection: $systemVoiceID) {
                    Text("Default").tag("")
                    ForEach(systemVoices, id: \.identifier) { v in
                        Text("\(v.name) (\(v.language))").tag(v.identifier)
                    }
                }
            }
            Toggle("Stream playback (low-latency)", isOn: $useStreaming)
                .toggleStyle(.switch)
            HStack {
                Button {
                    Task { await sampleSpeak() }
                } label: {
                    Label("Play sample", systemImage: "play.circle")
                }
                .disabled(!isCurrentTTSReady)
                Spacer()
                if playback.isPlaying || playback.duration != nil {
                    PlaybackControlsBar(playback: playback)
                }
            }
            if !sampleStatus.isEmpty {
                Text(sampleStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Spoken replies")
        } footer: {
            Text(ttsFootnote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var isCurrentTTSReady: Bool {
        if ttsEngine == "system" { return true }
        return KeychainAPIKeyProvider.isConfigured(providerID: providerKeyAccount(for: ttsEngine))
    }

    private func providerKeyAccount(for engine: String) -> String {
        switch engine {
        case "elevenlabs", "elevenlabs-music": return "elevenlabs"
        case "openai-tts":                     return "openai"
        case "cartesia":                       return "cartesia"
        case "suno":                           return "suno"
        case "stable-audio":                   return "stability"
        default:                               return engine
        }
    }

    private var ttsFootnote: String {
        switch ttsEngine {
        case "system":     return "AVSpeechSynthesizer. Free, on-device, ~60 system voices."
        case "elevenlabs": return "Voice cloning, 30+ languages. Bills your ElevenLabs account."
        case "openai-tts": return "Six built-in voices (alloy/echo/fable/onyx/nova/shimmer). Uses your OpenAI key."
        case "cartesia":   return "Sonic — ~40 ms first-byte. Best for real-time agents."
        default: return ""
        }
    }

    @MainActor
    private func sampleSpeak() async {
        let text = "Hello — this is the currently selected voice."
        do {
            if ttsEngine == "system" {
                let utt = AVSpeechUtterance(string: text)
                if !systemVoiceID.isEmpty,
                   let voice = AVSpeechSynthesisVoice(identifier: systemVoiceID) {
                    utt.voice = voice
                }
                AVSpeechSynthesizer().speak(utt)
                sampleStatus = "Speaking…"
                return
            }
            guard let provider = try VoiceRouter.shared.activeCloudTTSProvider() else { return }
            let voiceID = cloudVoiceID.isEmpty ? nil : cloudVoiceID

            if useStreaming && provider.supportsStreaming {
                let stream = provider.synthesizeStream(text: text, voiceID: voiceID, format: .mp3)
                await streamingPlayer.play(stream: stream, format: .mp3)
                sampleStatus = "Streaming \(provider.displayName)…"
            } else {
                let result = try await provider.synthesize(text: text, voiceID: voiceID, format: .mp3)
                try playback.play(result)
                sampleStatus = "Playing \(provider.displayName)…"
            }
        } catch {
            sampleStatus = "Sample failed: \(error)"
        }
    }

    // MARK: - Cartesia voices

    @ViewBuilder
    private var cartesiaVoiceSection: some View {
        if ttsEngine == "cartesia" {
            Section {
                if let err = cartesiaLoadError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                TextField("Search voices", text: $cartesiaSearch)
                    .textFieldStyle(.roundedBorder)
                Picker("Voice", selection: $cloudVoiceID) {
                    Text("Default").tag("")
                    ForEach(filteredCartesia, id: \.id) { voice in
                        Text("\(voice.displayName) — \(voice.language ?? "?")").tag(voice.id)
                    }
                }
                .disabled(cartesiaVoices.isEmpty)
                Button("Refresh voices") {
                    Task { await loadCartesiaVoices() }
                }
                .disabled(!KeychainAPIKeyProvider.isConfigured(providerID: "cartesia"))
            } header: {
                Text("Cartesia voices")
            } footer: {
                Text("Loads the voices your account has access to.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .task {
                if cartesiaVoices.isEmpty,
                   KeychainAPIKeyProvider.isConfigured(providerID: "cartesia") {
                    await loadCartesiaVoices()
                }
            }
        }
    }

    private var filteredCartesia: [TTSVoice] {
        guard !cartesiaSearch.isEmpty else { return cartesiaVoices }
        let q = cartesiaSearch.lowercased()
        return cartesiaVoices.filter {
            $0.displayName.lowercased().contains(q)
                || ($0.language?.lowercased().contains(q) ?? false)
        }
    }

    @MainActor
    private func loadCartesiaVoices() async {
        cartesiaLoadError = nil
        let provider = CartesiaTTSProvider(
            apiKeyProvider: KeychainAPIKeyProvider.for("cartesia")
        )
        do {
            cartesiaVoices = try await provider.voices()
        } catch {
            cartesiaLoadError = "Couldn't load voices: \(error)"
        }
    }

    // MARK: - Music

    private var musicSection: some View {
        Section {
            Picker("Provider", selection: $musicProvider) {
                Text("Suno (V5.5)").tag("suno")
                Text("ElevenLabs Music").tag("elevenlabs-music")
                Text("Stable Audio").tag("stable-audio")
            }
        } header: {
            Text("Music generation")
        } footer: {
            Text(musicFootnote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var musicFootnote: String {
        switch musicProvider {
        case "suno":             return "Routed via sunoapi.org. Full song generation including lyrics; ~30–90 s job."
        case "elevenlabs-music": return "Direct-response music API; up to 60-second clips. Same key as ElevenLabs TTS."
        case "stable-audio":     return "Stability AI Stable Audio 2; up to ~3-minute clips."
        default: return ""
        }
    }

    // MARK: - Cloud keys

    private var cloudKeysSection: some View {
        Section {
            CloudKeyRow(
                title: "ElevenLabs",
                placeholder: "xi-...",
                account: "elevenlabs",
                signupURL: URL(string: "https://elevenlabs.io/app/settings/api-keys")!,
                blurb: "Voice cloning + music"
            )
            CloudKeyRow(
                title: "OpenAI",
                placeholder: "sk-...",
                account: "openai",
                signupURL: URL(string: "https://platform.openai.com/api-keys")!,
                blurb: "TTS + (used by the daemon too)"
            )
            CloudKeyRow(
                title: "Cartesia",
                placeholder: "secret_...",
                account: "cartesia",
                signupURL: URL(string: "https://play.cartesia.ai/keys")!,
                blurb: "Sonic — 40 ms first byte"
            )
            CloudKeyRow(
                title: "Suno (via sunoapi.org)",
                placeholder: "...",
                account: "suno",
                signupURL: URL(string: "https://sunoapi.org/api-key")!,
                blurb: "Music generation, V5.5"
            )
            CloudKeyRow(
                title: "Stability AI",
                placeholder: "sk-...",
                account: "stability",
                signupURL: URL(string: "https://platform.stability.ai/account/keys")!,
                blurb: "Stable Audio 2 music"
            )
        } header: {
            Text("Provider keys")
        } footer: {
            Text("Stored in iOS Keychain under service `ai.swoosh.secrets`. Tap the link to open each provider's dashboard.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var systemVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().sorted {
            $0.language < $1.language
                || ($0.language == $1.language && $0.name < $1.name)
        }
    }
}

// MARK: - Playback controls

private struct PlaybackControlsBar: View {
    @Bindable var playback: TTSPlayback
    @State private var sliderValue: Double = 0
    @State private var isScrubbing: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if playback.isPlaying { playback.pause() } else { playback.resume() }
            } label: {
                Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 22))
            }
            .buttonStyle(.borderless)
            if let dur = playback.duration, dur > 0 {
                Slider(value: $sliderValue,
                       in: 0...dur,
                       onEditingChanged: { editing in
                           isScrubbing = editing
                           if !editing {
                               playback.seek(to: sliderValue)
                           }
                       })
                    .frame(width: 100)
                    .onChange(of: playback.currentTime) { _, new in
                        if !isScrubbing { sliderValue = new }
                    }
                Text(format(playback.currentTime) + " / " + format(dur))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Menu {
                ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                    Button("\(rate, specifier: "%.2g")×") {
                        playback.rate = Float(rate)
                    }
                }
            } label: {
                Text("\(playback.rate, specifier: "%.2g")×")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .center)
            }
            .buttonStyle(.borderless)
        }
    }

    private func format(_ t: TimeInterval) -> String {
        let total = Int(t)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Cloud key entry row

private struct CloudKeyRow: View {
    let title: String
    let placeholder: String
    let account: String
    let signupURL: URL
    let blurb: String

    @Environment(\.openURL) private var openURL
    @State private var draft: String = ""
    @State private var isSet: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .medium))
                    Text(blurb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(isSet ? "Key saved" : "Key not set")
                        .font(.caption2)
                        .foregroundStyle(isSet ? .green : .secondary)
                }
                Spacer()
                if isSet {
                    Button("Clear", role: .destructive) {
                        KeychainAPIKeyProvider.delete(providerID: account)
                        isSet = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    SecureField(placeholder, text: $draft)
                        .frame(width: 160)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { save() }
                }
            }
            HStack(spacing: 12) {
                Button {
                    openURL(signupURL)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                        Text("Get key")
                    }
                    .font(.caption)
                }
                .buttonStyle(.borderless)
                Text(signupURL.host ?? "")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .task { isSet = KeychainAPIKeyProvider.isConfigured(providerID: account) }
    }

    private func save() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if KeychainAPIKeyProvider.write(providerID: account, value: trimmed) {
            isSet = true
            draft = ""
        }
    }
}
