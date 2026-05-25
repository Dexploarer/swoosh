// DetourSpeechService.swift — local spoken onboarding prompts (0.5A)

import AVFoundation
import OSLog

private let detourSpeechLog = Logger(subsystem: "ai.swoosh.detour.mac", category: "Speech")

@MainActor
final class DetourSpeechService: NSObject, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    private let omniVoice = DetourOmniVoiceDesktopRenderer()
    private var localAudioPlayer: AVAudioPlayer?
    private var localAudioPlayerID: ObjectIdentifier?
    private var speakTask: Task<Void, Never>?
    private var speechCompletion: CheckedContinuation<Void, Never>?
    private var activeSpeechID: UUID?

    override init() {
        super.init()
        synthesizer.delegate = self
        Task { [omniVoice] in
            do {
                try await omniVoice.prepare()
            } catch {
                detourSpeechLog.error("[DetourSpeechService] OmniVoice prepare failed error=\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func stop() {
        let speechID = activeSpeechID
        speakTask?.cancel()
        speakTask = nil
        localAudioPlayer?.delegate = nil
        localAudioPlayer?.stop()
        localAudioPlayer = nil
        localAudioPlayerID = nil
        synthesizer.stopSpeaking(at: .immediate)
        if let speechID {
            finishSpeech(speechID: speechID)
        }
    }

    func speak(_ text: String, speech: DetourConfig.Speech) {
        startSpeaking(text, speech: speech, completion: nil)
    }

    func speakAndWait(_ text: String, speech: DetourConfig.Speech) async {
        await withCheckedContinuation { continuation in
            startSpeaking(text, speech: speech, completion: continuation)
        }
    }

    private func startSpeaking(
        _ text: String,
        speech: DetourConfig.Speech,
        completion: CheckedContinuation<Void, Never>?
    ) {
        stop()
        let speechID = UUID()
        activeSpeechID = speechID
        speechCompletion = completion

        speakTask = Task { [weak self, speechID] in
            guard let self else { return }
            do {
                let reference = referenceAudioForSpeech()
                let output = try await omniVoice.render(
                    text: text,
                    referenceAudio: reference?.audio,
                    referenceText: reference?.text
                )
                if Task.isCancelled {
                    finishSpeech(speechID: speechID)
                    return
                }
                try playLocalAudio(at: output, speechID: speechID)
            } catch {
                detourSpeechLog.error("[DetourSpeechService] OmniVoice render failed error=\(error.localizedDescription, privacy: .public)")
                finishSpeech(speechID: speechID)
            }
        }
    }

    private func referenceAudioForSpeech() -> (audio: URL, text: String?)? {
        do {
            guard let profile = try DetourStateStore().loadProfile(),
                  profile.voiceRecognition.enabled,
                  profile.voiceRecognition.enrolledAt != nil,
                  profile.voiceRecognition.sampleRelativePath != nil else {
                return nil
            }
            let sample = DetourPaths.directories().voiceEnrollmentSample
            guard FileManager.default.fileExists(atPath: sample.path(percentEncoded: false)) else {
                return nil
            }
            return (sample, profile.voiceRecognition.enrollmentPhrase)
        } catch {
            return nil
        }
    }

    private func playLocalAudio(at url: URL, speechID: UUID) throws {
        guard activeSpeechID == speechID else { return }
        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self
        localAudioPlayer = player
        localAudioPlayerID = ObjectIdentifier(player)
        player.prepareToPlay()
        guard player.play() else {
            throw NSError(
                domain: "ai.swoosh.detour.speech",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "AVAudioPlayer.play() returned false"]
            )
        }
    }

    private func finishSpeech(speechID: UUID) {
        guard activeSpeechID == speechID else { return }
        let completion = speechCompletion
        activeSpeechID = nil
        speechCompletion = nil
        localAudioPlayer?.delegate = nil
        localAudioPlayer = nil
        localAudioPlayerID = nil
        completion?.resume()
    }

    private func finishSpeech(playerID: ObjectIdentifier) {
        guard localAudioPlayerID == playerID, let activeSpeechID else { return }
        finishSpeech(speechID: activeSpeechID)
    }
}

extension DetourSpeechService: AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let playerID = ObjectIdentifier(player)
        Task { @MainActor in
            finishSpeech(playerID: playerID)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard let activeSpeechID else { return }
            finishSpeech(speechID: activeSpeechID)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard let activeSpeechID else { return }
            finishSpeech(speechID: activeSpeechID)
        }
    }
}
