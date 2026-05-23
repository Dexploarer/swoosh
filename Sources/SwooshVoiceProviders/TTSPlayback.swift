// SwooshVoiceProviders/TTSPlayback.swift — 0.9R AVAudioPlayer wrapper + queue
//
// Plays raw audio Data (from any TTS provider) through AVAudioPlayer,
// with simple FIFO queueing so back-to-back synthesize calls play in
// order. Designed for short utterances (a turn of an agent reply).
//
// API:
//   let player = TTSPlayback()
//   try await player.play(result)              // single
//   await player.enqueue(result)               // FIFO; current finishes first
//   await player.stop()
//   player.isPlaying / player.queueDepth

import Foundation
import AVFoundation

@MainActor
@Observable
public final class TTSPlayback: NSObject {

    public private(set) var isPlaying: Bool = false
    public private(set) var queueDepth: Int = 0
    public private(set) var currentResult: TTSResult?

    /// Live playback position in seconds. Updated on a 200 ms timer.
    public private(set) var currentTime: TimeInterval = 0

    /// Total duration of the active utterance. nil while loading.
    public private(set) var duration: TimeInterval?

    /// 0…1 — driven by AVAudioPlayer.volume (system volume separate).
    public var volume: Float = 1.0 {
        didSet { player?.volume = max(0, min(1, volume)) }
    }

    /// 0.5 – 2.0. AVAudioPlayer.enableRate is enabled in startPlaying.
    public var rate: Float = 1.0 {
        didSet { player?.rate = max(0.5, min(2.0, rate)) }
    }

    private var player: AVAudioPlayer?
    private var queue: [TTSResult] = []
    private var positionTimer: Timer?

    /// Average power of the current playback in dB (negative). nil when
    /// nothing is playing. Used by visualisers (liquid voice sphere) and
    /// the haptics coordinator to react to the agent's outgoing voice.
    public func averagePowerDB() -> Float? {
        guard let player, player.isPlaying else { return nil }
        player.isMeteringEnabled = true
        player.updateMeters()
        return player.averagePower(forChannel: 0)
    }

    public override init() {
        super.init()
        configureAudioSession()
    }

    /// Stop whatever's playing and play this immediately.
    public func play(_ result: TTSResult) throws {
        try stopInternal()
        queue.removeAll()
        queueDepth = 0
        try startPlaying(result)
    }

    /// Append to queue. Plays now if nothing's playing.
    public func enqueue(_ result: TTSResult) throws {
        if player?.isPlaying == true {
            queue.append(result)
            queueDepth = queue.count
        } else {
            try startPlaying(result)
        }
    }

    public func pause() {
        player?.pause()
        isPlaying = false
        stopPositionTimer()
    }

    public func resume() {
        if let p = player {
            p.play()
            isPlaying = p.isPlaying
            startPositionTimer()
        }
    }

    /// Jump to a position in the current utterance.
    public func seek(to seconds: TimeInterval) {
        guard let player else { return }
        player.currentTime = max(0, min(player.duration, seconds))
        currentTime = player.currentTime
    }

    /// Skip forward/back relative to current position.
    public func skip(by delta: TimeInterval) {
        guard let player else { return }
        seek(to: player.currentTime + delta)
    }

    public func stop() {
        try? stopInternal()
        queue.removeAll()
        queueDepth = 0
    }

    /// Convenience: synthesize and play in one call.
    public func speak(_ text: String, with provider: any TTSProviding) async throws {
        let result = try await provider.synthesize(
            text: text,
            voiceID: nil,
            format: .mp3
        )
        try play(result)
    }

    // MARK: - Internals

    private func startPlaying(_ result: TTSResult) throws {
        let player = try AVAudioPlayer(data: result.audioData)
        player.delegate = self
        player.enableRate = true
        player.volume = volume
        player.rate = rate
        player.prepareToPlay()
        guard player.play() else {
            throw NSError(domain: "ai.swoosh.tts", code: -1, userInfo: [NSLocalizedDescriptionKey: "AVAudioPlayer.play() returned false"])
        }
        self.player = player
        self.currentResult = result
        self.duration = player.duration
        self.currentTime = 0
        self.isPlaying = true
        startPositionTimer()
    }

    private func stopInternal() throws {
        player?.stop()
        player = nil
        currentResult = nil
        isPlaying = false
        duration = nil
        currentTime = 0
        stopPositionTimer()
    }

    // MARK: - Position polling

    private func startPositionTimer() {
        stopPositionTimer()
        positionTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
            }
        }
    }

    private func stopPositionTimer() {
        positionTimer?.invalidate()
        positionTimer = nil
    }

    private func configureAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        #endif
    }
}

extension TTSPlayback: AVAudioPlayerDelegate {
    public nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.player = nil
            self.currentResult = nil
            self.isPlaying = false
            if !self.queue.isEmpty {
                let next = self.queue.removeFirst()
                self.queueDepth = self.queue.count
                try? self.startPlaying(next)
            }
        }
    }
}
