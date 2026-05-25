// DetouriOSSpeechService.swift — native spoken onboarding prompts for iPhone (0.5A)

import AVFoundation
import FluidAudio
import Foundation

@MainActor
final class DetouriOSSpeechService: NSObject, ObservableObject {
    enum LocalVoiceState: Equatable {
        case idle
        case warming
        case ready
        case failed(String)
    }

    @Published private(set) var localVoiceState: LocalVoiceState = .idle
    @Published private(set) var kokoroAssetsAvailable = DetouriOSSpeechService.hasCachedKokoroAssets()
    @Published private(set) var prefersLocalVoice = true

    private var kokoroManager: KokoroAneManager?
    private var localAudioPlayer: AVAudioPlayer?
    private var warmupTask: Task<Void, Never>?
    private var assetInstallTask: Task<Void, Never>?
    private var speakTask: Task<Void, Never>?
    private var speechSerial = 0

    override init() {
        super.init()
        DetouriOSVoiceSettings.useDefaultLocalVoice()
    }

    var localVoiceTitle: String {
        "Kokoro"
    }

    var localVoiceIsPreparing: Bool {
        localVoiceState == .warming
    }

    var canRetryLocalVoice: Bool {
        switch localVoiceState {
        case .idle, .failed:
            true
        case .warming, .ready:
            false
        }
    }

    var hasLocalVoiceChoice: Bool {
        kokoroManager != nil || kokoroAssetsAvailable || Self.canInstallKokoroAssets
    }

    func prepareLocalVoice() {
        if !kokoroAssetsAvailable {
            kokoroAssetsAvailable = Self.hasCachedKokoroAssets()
        }
        guard kokoroAssetsAvailable else {
            localVoiceState = .idle
            prefetchLocalVoiceAssets()
            return
        }
        if kokoroManager != nil {
            localVoiceState = .ready
            return
        }
        guard warmupTask == nil else { return }
        localVoiceState = .warming
        warmupTask = Task { [weak self] in
            let voiceID = DetouriOSVoiceSettings.selectedKokoroVoiceID
            let manager = KokoroAneManager(defaultVoice: voiceID)
            do {
                try await manager.initialize(preloadVoices: [voiceID])
                if Task.isCancelled { return }
                await MainActor.run {
                    self?.kokoroManager = manager
                    self?.localVoiceState = .ready
                    self?.warmupTask = nil
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    self?.localVoiceState = .failed(error.localizedDescription)
                    self?.warmupTask = nil
                }
            }
        }
    }

    func selectLocalVoice() {
        DetouriOSVoiceSettings.useDefaultLocalVoice()
        prefersLocalVoice = true
        prepareLocalVoice()
    }

    func prefetchLocalVoiceAssets() {
        guard !kokoroAssetsAvailable, assetInstallTask == nil else { return }
        assetInstallTask = Task { [weak self] in
            do {
                try await KokoroAneResourceDownloader.ensureModels(variant: .english)
                try await KokoroAneResourceDownloader.ensureG2PAssets()
                if Task.isCancelled { return }
                await MainActor.run {
                    self?.kokoroAssetsAvailable = Self.hasCachedKokoroAssets()
                    self?.assetInstallTask = nil
                    self?.prepareLocalVoice()
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    self?.assetInstallTask = nil
                }
            }
        }
    }

    func speak(_ text: String, speech _: DetouriOSConfig.Speech) {
        let serial = beginSpeech()
        speakTask = Task { [weak self] in
            await self?.speakLocal(text, serial: serial)
        }
    }

    func speakAndWait(_ text: String, speech _: DetouriOSConfig.Speech) async {
        let serial = beginSpeech()
        await speakLocal(text, serial: serial)
    }

    func stop() {
        speechSerial += 1
        speakTask?.cancel()
        speakTask = nil
        localAudioPlayer?.stop()
        localAudioPlayer = nil
    }

    private func beginSpeech() -> Int {
        speechSerial += 1
        speakTask?.cancel()
        speakTask = nil
        localAudioPlayer?.stop()
        localAudioPlayer = nil
        DetouriOSVoiceSettings.useDefaultLocalVoice()
        prefersLocalVoice = true
        return speechSerial
    }

    private func speakLocal(_ text: String, serial: Int) async {
        guard let manager = await managerForSpeech(),
              !Task.isCancelled,
              serial == speechSerial else {
            return
        }

        do {
            let audioData = try await manager.synthesize(
                text: text,
                voice: DetouriOSVoiceSettings.selectedKokoroVoiceID
            )
            guard !Task.isCancelled, serial == speechSerial else { return }

            let player = try AVAudioPlayer(data: audioData)
            localAudioPlayer = player
            player.prepareToPlay()
            guard player.play() else { return }

            let playbackMilliseconds = max(250, Int((player.duration + 0.2) * 1_000))
            try? await Task.sleep(for: .milliseconds(playbackMilliseconds))
            if serial == speechSerial {
                localAudioPlayer = nil
            }
        } catch {
            if !Task.isCancelled, serial == speechSerial {
                localVoiceState = .failed(error.localizedDescription)
            }
        }
    }

    private func managerForSpeech() async -> KokoroAneManager? {
        if let kokoroManager {
            return kokoroManager
        }
        prepareLocalVoice()
        if let warmupTask {
            await warmupTask.value
        }
        return kokoroManager
    }

    static func hasCachedKokoroAssets() -> Bool {
        guard let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return false
        }
        let repoURL = cacheURL
            .appendingPathComponent("fluidaudio")
            .appendingPathComponent("Models")
            .appendingPathComponent("kokoro-82m-coreml")
            .appendingPathComponent("ANE")
        let g2pURL = cacheURL
            .appendingPathComponent("fluidaudio")
            .appendingPathComponent("Models")
            .appendingPathComponent("kokoro")
        let requiredFiles = [
            "KokoroAlbert.mlmodelc",
            "KokoroPostAlbert.mlmodelc",
            "KokoroAlignment.mlmodelc",
            "KokoroProsody.mlmodelc",
            "KokoroNoise.mlmodelc",
            "KokoroVocoder.mlmodelc",
            "KokoroTail.mlmodelc",
            "vocab.json",
            "af_heart.bin"
        ]
        let requiredG2PFiles = [
            "G2PEncoder.mlmodelc",
            "G2PDecoder.mlmodelc",
            "g2p_vocab.json"
        ]
        return requiredFiles.allSatisfy { fileName in
            FileManager.default.fileExists(atPath: repoURL.appendingPathComponent(fileName).path)
        } && requiredG2PFiles.allSatisfy { fileName in
            FileManager.default.fileExists(atPath: g2pURL.appendingPathComponent(fileName).path)
        }
    }

    static var canInstallKokoroAssets: Bool {
        true
    }
}
