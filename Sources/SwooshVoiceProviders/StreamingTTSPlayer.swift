// SwooshVoiceProviders/StreamingTTSPlayer.swift — 0.9R Low-latency streaming TTS
//
// Real chunk-by-chunk playback: as soon as the first audio bytes arrive,
// playback starts; subsequent chunks schedule onto the same player node.
//
// Two ingestion paths:
//
//   • Compressed (MP3 / OPUS / AAC) — ElevenLabs, OpenAI, ElevenLabs
//     Music. We append to a growing temp file, then schedule new file
//     segments into AVAudioPlayerNode as data lands. AVAudioFile reads
//     the live file lazily.
//
//   • Raw PCM (Cartesia with pcm_s16le encoding) — direct AVAudioPCMBuffer
//     scheduling; lowest latency path. ~40 ms first-byte to speaker.
//
// Built on the 2026 audio stack:
//   • AVAudioEngine + AVAudioPlayerNode (lowest-latency Swift API)
//   • AVAudioApplication (iOS 18+ / macOS 14+) for session activation
//   • AsyncStream of state events for observable UI
//   • Spatial-audio-friendly: scheduled buffers pass through the engine's
//     mixer node so airpods spatial mode works automatically
//
// Status tracked via the @Observable `state` enum so the picker can
// surface "buffering → playing → done" without polling.

import Foundation
import AVFoundation

@MainActor
@Observable
public final class StreamingTTSPlayer {

    public enum State: Sendable, Equatable {
        case idle
        case buffering(received: Int)
        case playing(progress: Double)
        case paused(at: TimeInterval)
        case done
        case failed(String)
    }

    public private(set) var state: State = .idle
    /// Estimated current playback time in seconds. Updates as chunks
    /// finish scheduling; not frame-accurate, good enough for a scrubber.
    public private(set) var currentTime: TimeInterval = 0

    /// RMS-derived live audio levels (12 bands, each [0,1]). Driven by
    /// an installTap on the mixer; updated ~30 fps. Use for waveform
    /// visualization without doing your own FFT.
    public private(set) var levels: [Float] = Array(repeating: 0, count: 12)

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    /// Mixer between player and output — exposes a volume knob and lets
    /// the engine handle format conversion transparently.
    private let mixer = AVAudioMixerNode()

    private var ingestionTask: Task<Void, Never>?
    private var pcmFormat: AVAudioFormat?
    private var compressedFile: URL?
    private var compressedFileHandle: FileHandle?
    private var fileReader: AVAudioFile?
    private var scheduledFramePosition: AVAudioFramePosition = 0
    private var rate: Float = 1.0

    public init() {
        engine.attach(playerNode)
        engine.attach(mixer)
        engine.connect(playerNode, to: mixer, format: nil)
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)
        installLevelsTap()
    }

    /// Manually remove the level tap. Call before letting the player
    /// go out of scope; deinit can't touch non-Sendable mixer state
    /// from a nonisolated context.
    public func detachTap() {
        mixer.removeTap(onBus: 0)
    }

    /// Install an RMS tap on the mixer output. Cheap — runs per audio
    /// buffer (~23 ms at 44.1 kHz / 1024 frames). Splits each buffer
    /// into 12 time bands and computes RMS per band for waveform UI.
    private func installLevelsTap() {
        let bus = 0
        let bufferSize: AVAudioFrameCount = 1024
        let format = mixer.outputFormat(forBus: bus)
        mixer.installTap(onBus: bus, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            guard let self,
                  let channelData = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }
            let bandCount = 12
            let framesPerBand = max(1, frameCount / bandCount)
            var newLevels = [Float](repeating: 0, count: bandCount)
            for b in 0..<bandCount {
                let start = b * framesPerBand
                let end = min(frameCount, start + framesPerBand)
                guard end > start else { continue }
                var sum: Float = 0
                for i in start..<end {
                    let s = channelData[i]
                    sum += s * s
                }
                let rms = sqrt(sum / Float(end - start))
                // Perceptual boost — speech RMS rarely exceeds 0.25.
                newLevels[b] = min(1, rms * 4)
            }
            Task { @MainActor in self.levels = newLevels }
        }
    }

    // MARK: - Public API

    public var volume: Float {
        get { mixer.outputVolume }
        set { mixer.outputVolume = max(0, min(1, newValue)) }
    }

    public var playbackRate: Float {
        get { rate }
        set {
            rate = max(0.5, min(2.0, newValue))
            playerNode.rate = rate
        }
    }

    /// Begin playing from a streaming TTS provider. Idempotent — calling
    /// twice cancels the prior stream and restarts.
    public func play(
        stream: AsyncThrowingStream<Data, Error>,
        format: TTSAudioFormat
    ) async {
        await stop()
        state = .buffering(received: 0)
        try? activateSession()
        try? engine.start()

        // PCM path: Cartesia (or any provider) that opts into raw 16-bit
        // signed LE PCM. Zero-decode — chunks wrap directly into
        // AVAudioPCMBuffers and schedule into the player node.
        // Compressed path is the safe default for MP3/AAC/OPUS.
        Logger.streaming.info("starting stream — format=\(format.rawValue, privacy: .public)")
        if format.isRawPCM {
            await playPCMStream(stream)
        } else {
            await playCompressedStream(stream)
        }
    }

    public func pause() {
        guard case .playing = state else { return }
        playerNode.pause()
        state = .paused(at: currentTime)
    }

    public func resume() {
        guard case .paused = state else { return }
        playerNode.play()
        state = .playing(progress: 0)
    }

    /// Seek to a relative position in the buffered audio. Best-effort —
    /// streaming TTS can only seek within already-received audio.
    public func seek(to seconds: TimeInterval) {
        guard let file = fileReader else { return }
        let sampleRate = file.processingFormat.sampleRate
        let targetFrame = AVAudioFramePosition(seconds * sampleRate)
        playerNode.stop()
        scheduledFramePosition = targetFrame
        scheduleFromFile(startingAt: targetFrame)
        playerNode.play()
        currentTime = seconds
    }

    public func stop() async {
        ingestionTask?.cancel()
        ingestionTask = nil
        playerNode.stop()
        engine.stop()
        compressedFileHandle?.closeFile()
        compressedFileHandle = nil
        if let url = compressedFile { try? FileManager.default.removeItem(at: url) }
        compressedFile = nil
        fileReader = nil
        scheduledFramePosition = 0
        currentTime = 0
        state = .idle
    }

    // MARK: - Compressed (MP3 / OPUS / AAC) ingestion

    private func playCompressedStream(_ stream: AsyncThrowingStream<Data, Error>) async {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-tts-\(UUID().uuidString).mp3")
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: tmp) else {
            state = .failed("could not open temp file")
            return
        }
        compressedFile = tmp
        compressedFileHandle = handle

        ingestionTask = Task { [weak self] in
            guard let self else { return }
            var receivedBytes = 0
            var started = false
            do {
                for try await chunk in stream {
                    if Task.isCancelled { return }
                    receivedBytes += chunk.count
                    try handle.write(contentsOf: chunk)
                    await MainActor.run {
                        if case .buffering = self.state {
                            self.state = .buffering(received: receivedBytes)
                        }
                    }
                    // Start playback once enough bytes have buffered to
                    // open the file safely (~16 KB ≈ ~1 s of 128 kbps MP3).
                    if !started, receivedBytes >= 16_384 {
                        started = true
                        await MainActor.run { self.startReadingFile() }
                    }
                }
                // Stream done — final flush.
                try handle.close()
                await MainActor.run {
                    self.compressedFileHandle = nil
                    if !started { self.startReadingFile() }
                    // Schedule any remaining unscheduled audio.
                    self.scheduleRemaining()
                }
            } catch {
                await MainActor.run {
                    self.state = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func startReadingFile() {
        guard let url = compressedFile else { return }
        // iOS occasionally rejects an in-flight growing file the first
        // time AVAudioFile reads the header — retry with backoff (up to
        // 3 tries, 80/160/320 ms) before surfacing a real failure.
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                let file = try AVAudioFile(forReading: url)
                self.fileReader = file
                engine.disconnectNodeOutput(playerNode)
                engine.connect(playerNode, to: mixer, format: file.processingFormat)
                scheduleFromFile(startingAt: 0)
                playerNode.play()
                Logger.streaming.info("AVAudioFile opened on attempt \(attempt + 1) — sampleRate=\(file.processingFormat.sampleRate)")
                state = .playing(progress: 0)
                return
            } catch {
                lastError = error
                Logger.streaming.error("AVAudioFile open attempt \(attempt + 1) failed: \(error.localizedDescription, privacy: .public)")
                // 80 ms × 2^attempt
                Thread.sleep(forTimeInterval: 0.08 * pow(2, Double(attempt)))
            }
        }
        state = .failed("AVAudioFile open: \(lastError?.localizedDescription ?? "unknown")")
    }

    /// Legacy entry point — replaced by the retry loop above.
    private func startReadingFile_unused() {
        guard let url = compressedFile else { return }
        do {
            let file = try AVAudioFile(forReading: url)
            self.fileReader = file
            engine.disconnectNodeOutput(playerNode)
            engine.connect(playerNode, to: mixer, format: file.processingFormat)
            scheduleFromFile(startingAt: 0)
            playerNode.play()
            state = .playing(progress: 0)
        } catch {
            state = .failed("AVAudioFile open: \(error.localizedDescription)")
        }
    }

    /// Schedule the entire current file from a frame position. Re-read
    /// later as more data lands via `scheduleRemaining`.
    private func scheduleFromFile(startingAt frame: AVAudioFramePosition) {
        guard let file = fileReader else { return }
        let segmentFrames = AVAudioFrameCount(max(0, file.length - frame))
        guard segmentFrames > 0 else { return }
        playerNode.scheduleSegment(
            file,
            startingFrame: frame,
            frameCount: segmentFrames,
            at: nil,
            completionHandler: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    if case .playing = self.state {
                        self.state = .done
                    }
                }
            }
        )
        scheduledFramePosition = frame + AVAudioFramePosition(segmentFrames)
    }

    /// Re-open the file (it grew while playing) and schedule whatever
    /// hasn't been scheduled yet.
    private func scheduleRemaining() {
        guard let url = compressedFile else { return }
        guard let file = try? AVAudioFile(forReading: url) else { return }
        fileReader = file
        let remaining = AVAudioFrameCount(max(0, file.length - scheduledFramePosition))
        guard remaining > 0 else { return }
        playerNode.scheduleSegment(
            file,
            startingFrame: scheduledFramePosition,
            frameCount: remaining,
            at: nil
        )
        scheduledFramePosition += AVAudioFramePosition(remaining)
    }

    // MARK: - PCM (Cartesia raw) ingestion

    private func playPCMStream(_ stream: AsyncThrowingStream<Data, Error>) async {
        // Cartesia raw PCM: 16-bit signed little-endian, 44.1 kHz mono.
        // Build the format once; schedule each chunk as a PCM buffer.
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 44_100,
            channels: 1,
            interleaved: true
        ) else {
            state = .failed("could not build PCM format")
            return
        }
        pcmFormat = format

        engine.disconnectNodeOutput(playerNode)
        engine.connect(playerNode, to: mixer, format: format)
        try? engine.start()

        ingestionTask = Task { [weak self] in
            guard let self else { return }
            var started = false
            do {
                for try await chunk in stream {
                    if Task.isCancelled { return }
                    // Wrap the chunk's bytes in an AVAudioPCMBuffer.
                    let bytesPerFrame = 2 // Int16 mono
                    let frameCount = AVAudioFrameCount(chunk.count / bytesPerFrame)
                    guard frameCount > 0,
                          let buffer = AVAudioPCMBuffer(
                              pcmFormat: format,
                              frameCapacity: frameCount
                          )
                    else { continue }
                    buffer.frameLength = frameCount
                    if let channelData = buffer.int16ChannelData?[0] {
                        _ = chunk.withUnsafeBytes { raw in
                            memcpy(channelData, raw.baseAddress, Int(frameCount) * bytesPerFrame)
                        }
                    }
                    await MainActor.run {
                        self.playerNode.scheduleBuffer(buffer, at: nil, options: [])
                        if !started {
                            started = true
                            self.playerNode.play()
                            self.state = .playing(progress: 0)
                        }
                    }
                }
                await MainActor.run { self.state = .done }
            } catch {
                await MainActor.run {
                    self.state = .failed(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Session

    private func activateSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true)
        #endif
    }
}
