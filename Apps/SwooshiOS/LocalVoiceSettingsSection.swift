// Apps/SwooshiOS/LocalVoiceSettingsSection.swift — 0.9R Voice picker integrations
//
// Two small views the existing `VoicePickerScreen` composes in:
//   • `LocalVoicePickerOptions`  — `Picker` children for Kokoro + OmniVoice
//   • `LocalVoiceCatalogSection` — list section with download rows
//
// Kept in a separate file so the existing 500-line VoicePickerScreen
// doesn't grow indefinitely each time a new on-device engine ships.

import SwiftUI
#if os(iOS)
import SwooshLocalVoice
#endif

/// Drop these `Picker` children into the TTS engine picker. Pickers
/// flatten nested Groups so the user sees flat options.
struct LocalVoicePickerOptions: View {
    var body: some View {
        Group {
            Text("Kokoro (on-device)").tag("kokoro-local")
            Text("StyleTTS2 (on-device, zero-shot clone)").tag("styletts2-local")
            Text("PocketTTS (on-device, persistent clone)").tag("pockettts-local")
            Text("OmniVoice (on-device, 600+ langs)").tag("omnivoice-local")
        }
    }
}

/// The "On-device voice models" Section that hosts the download rows
/// for every entry in `LocalVoiceCatalog.all`.
struct LocalVoiceCatalogSection: View {
    var body: some View {
        #if os(iOS)
        Section {
            ForEach(LocalVoiceCatalog.all) { model in
                LocalVoiceDownloadRow(model: model)
            }
        } header: {
            Text("On-device voice models")
        } footer: {
            Text("Kokoro is small (~325 MB) and runs on any iPhone. OmniVoice (~3.2 GB) needs a recent device with extended virtual addressing. Until an ONNX Runtime dep is wired, both fall back to Apple Speech for audio output — the download is staged so the swap is a single file.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        #else
        EmptyView()
        #endif
    }
}
