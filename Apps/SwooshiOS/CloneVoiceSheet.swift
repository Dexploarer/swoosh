// Apps/SwooshiOS/CloneVoiceSheet.swift — 0.9R Add a new voice clone
//
// Single-page sheet that lets the user pick a 3–10 s reference audio
// file (Files / Photos audio export), name it, and enroll it. The
// enrollment runs through PocketTtsManager.cloneVoice → encodes into
// the LocalVoiceCloneStore. On success, the new clone is selectable
// from `ClonedVoicesSection` in Settings.

import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import FluidAudio
import SwooshLocalVoice
#endif

struct CloneVoiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var referenceURL: URL? = nil
    @State private var importing = false
    @State private var enrolling = false
    @State private var errorText: String?
    let onCreated: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. My voice", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }
                Section {
                    Button {
                        importing = true
                    } label: {
                        Label(referenceURL == nil ? "Pick reference audio" : "Pick a different file",
                              systemImage: "waveform.badge.plus")
                    }
                    if let referenceURL {
                        Text(referenceURL.lastPathComponent)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                } footer: {
                    Text("Pick a 3–10 second clip in WAV, M4A, AIFF or CAF format. The clip stays on this device.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle("Clone a voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(enrolling ? "Enrolling…" : "Enroll") {
                        Task { await enroll() }
                    }
                    .disabled(!canEnroll || enrolling)
                }
            }
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        // Security-scoped URL: copy into temp so we own a stable path.
                        if let copied = copyToTemp(url) { referenceURL = copied }
                        else { errorText = "Couldn't read the picked file." }
                    }
                case .failure(let err): errorText = err.localizedDescription
                }
            }
        }
    }

    private var canEnroll: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && referenceURL != nil
    }

    @MainActor
    private func enroll() async {
        #if os(iOS)
        guard let referenceURL else { return }
        enrolling = true; defer { enrolling = false }
        errorText = nil
        do {
            let manager = PocketTtsManager()
            try await manager.initialize()
            let voiceData = try await manager.cloneVoice(from: referenceURL)
            let envelope = PocketCloneEnvelopeBridge(audioPrompt: voiceData.audioPrompt,
                                                     promptLength: voiceData.promptLength)
            let bytes = try JSONEncoder().encode(envelope)
            _ = try await LocalVoiceCloneStore.shared.add(
                name: name,
                voiceDataBytes: bytes,
                referenceAudio: referenceURL
            )
            onCreated()
            dismiss()
        } catch {
            errorText = String(describing: error)
        }
        #endif
    }

    private func copyToTemp(_ url: URL) -> URL? {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        let dst = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ref-\(UUID().uuidString).\(url.pathExtension)")
        do {
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: url, to: dst)
            return dst
        } catch { return nil }
    }
}

/// Mirror of PocketCloneEnvelope (which is internal to SwooshLocalVoice
/// for backend dispatch). Keeping a local copy here means the iOS app
/// doesn't need to expose the backend internals publicly.
private struct PocketCloneEnvelopeBridge: Codable {
    let audioPrompt: [Float]
    let promptLength: Int
}
