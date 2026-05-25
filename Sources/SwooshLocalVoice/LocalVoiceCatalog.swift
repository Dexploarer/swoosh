// SwooshLocalVoice/LocalVoiceCatalog.swift — 0.9R Built-in catalog
//
// The two voice models we actually ship in 2026: Kokoro (tiny, Apache-2.0,
// the best small TTS for on-device) and OmniVoice (Xiaomi/k2-fsa, Apache-2.0,
// the only credibly-on-device 600+-language model with voice cloning).
//
// URLs point at the canonical Hugging Face releases. The downloader does
// a simple GET — re-host or proxy if upstream changes layout.

import Foundation

private extension URL {
    static func staticURL(_ s: StaticString) -> URL {
        guard let url = URL(string: "\(s)") else { preconditionFailure("Invalid static URL: \(s)") }
        return url
    }
}

public enum LocalVoiceCatalog {

    public static let defaultKokoroVoiceID = "af_heart"

    /// Default selection — Kokoro is the safest "just works" option:
    /// 82M params, ~160 MB on disk, MIT, fits any iPhone shipped in the
    /// last five years.
    public static let defaultModel: LocalVoiceModel = kokoro

    /// Kokoro 82M (hexgrad), wired via `FluidAudio.KokoroAneManager` —
    /// the 7-stage ANE-resident CoreML pipeline. FluidAudio downloads
    /// the model into its own caches dir on first use (~80 MB INT8 quant).
    /// The download URL here points at the upstream CoreML bundle for
    /// documentation; the engine itself routes through FluidAudio's
    /// resource manager, not Swoosh's `LocalVoiceDownloader`.
    ///
    /// Upstream Kokoro is Apache-2.0; FluidAudio's CoreML port retains
    /// that license (see `FluidInference/kokoro-82m-coreml` model card).
    public static let kokoro = LocalVoiceModel(
        id: "kokoro-82m-v1",
        displayName: "Kokoro 82M (English + Mandarin)",
        family: "Kokoro",
        downloadURL: .staticURL("https://huggingface.co/FluidInference/kokoro-82m-coreml"),
        estimatedBytes: 80_000_000,
        parameters: "82M",
        license: "Apache-2.0",
        engineKind: .coreml,
        supportsVoiceCloning: false,
        languageCount: 2,
        defaultSampleRate: 24000
    )

    /// OmniVoice (Xiaomi/k2-fsa, March 2026). 600+ languages, zero-shot
    /// voice cloning. The full FP16 weights are large (~3.2 GB); pair
    /// with the `LiteRTDevicePolicy` so we don't try to load it on a
    /// 3 GB iPhone.
    public static let omniVoice = LocalVoiceModel(
        id: "omnivoice-v1",
        displayName: "OmniVoice (600+ languages, cloning)",
        family: "OmniVoice",
        downloadURL: .staticURL("https://huggingface.co/k2-fsa/OmniVoice/resolve/main/model.fp16.onnx"),
        estimatedBytes: 3_200_000_000,
        parameters: "~600M",
        license: "Apache-2.0",
        engineKind: .onnx,
        supportsVoiceCloning: true,
        languageCount: 646,
        defaultSampleRate: 22050
    )

    /// StyleTTS2 LibriTTS (iteration_3), wired via `FluidAudio.StyleTTS2Manager`.
    /// Zero-shot voice cloning per call — pass a 3–10 s reference WAV
    /// and the model speaks the input text in that voice. No enrollment
    /// step, so callers can hot-swap voices freely.
    public static let styleTTS2 = LocalVoiceModel(
        id: "styletts2-libri-v1",
        displayName: "StyleTTS2 (zero-shot cloning)",
        family: "StyleTTS2",
        downloadURL: .staticURL("https://huggingface.co/FluidInference/styletts2-libritts-coreml"),
        estimatedBytes: 220_000_000,
        parameters: "~150M",
        license: "MIT",
        engineKind: .coreml,
        supportsVoiceCloning: true,
        languageCount: 1,
        defaultSampleRate: 24000
    )

    /// PocketTTS, wired via `FluidAudio.PocketTtsManager`. Two-step
    /// cloning: `cloneVoice(from: URL) -> PocketTtsVoiceData`, then
    /// `synthesize(text: voiceData:)`. The enrollment blob is
    /// persistable, so cloned voices survive across launches.
    public static let pocketTTS = LocalVoiceModel(
        id: "pockettts-v1",
        displayName: "PocketTTS (persistent cloning)",
        family: "PocketTTS",
        downloadURL: .staticURL("https://huggingface.co/FluidInference/pockettts-coreml"),
        estimatedBytes: 180_000_000,
        parameters: "~100M",
        license: "Apache-2.0",
        engineKind: .coreml,
        supportsVoiceCloning: true,
        languageCount: 1,
        defaultSampleRate: 24000
    )

    /// Built-in catalog, smallest-first so the device-policy picker
    /// hands back Kokoro on the typical iPhone budget. Cloning entries
    /// (StyleTTS2, PocketTTS) sit between Kokoro and OmniVoice in size.
    public static let all: [LocalVoiceModel] = [kokoro, pocketTTS, styleTTS2, omniVoice]

    public static func model(id: String) -> LocalVoiceModel? {
        all.first(where: { $0.id == id })
    }

    /// Subset that advertises voice cloning. UI uses this to surface
    /// "Clone a voice" actions only when at least one is selectable.
    public static var cloningCapable: [LocalVoiceModel] {
        all.filter(\.supportsVoiceCloning)
    }
}
