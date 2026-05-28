// SwooshUI/AgentShell/SpeechCapture.swift — 0.9R On-device speech-to-text
//
// SFSpeechRecognizer + AVAudioEngine wrapper. Live partial transcripts
// stream into a published `transcript` string; when the user stops, the
// final transcript is committed into `AgentShellModel.input` and the
// model returns to `.idle`.
//
// Permission story:
//   • macOS 10.15+ / iOS 10+ — system handles permission UI.
//   • Mac app needs Info.plist keys: NSMicrophoneUsageDescription +
//     NSSpeechRecognitionUsageDescription.
//
// Failure modes are surfaced via `lastError` — the view can decide
// whether to show a banner or just silently drop the listening state.

import Foundation
import AVFoundation
@preconcurrency import Speech
import os

// Thread-safe float box for passing audio level from the realtime
// audio thread to the MainActor without isolation violations.
private final class AudioLevelBox: @unchecked Sendable {
    private var _value: Float = 0
    private var _lock = os_unfair_lock()

    func store(_ v: Float) {
        os_unfair_lock_lock(&_lock)
        _value = v
        os_unfair_lock_unlock(&_lock)
    }

    func load() -> Float {
        os_unfair_lock_lock(&_lock)
        let v = _value
        os_unfair_lock_unlock(&_lock)
        return v
    }
}

@MainActor
@Observable
public final class SpeechCapture {

    // ── Published state ──────────────────────────────────────────────

    /// The most recent partial transcript. Updates live while listening.
    public private(set) var transcript: String = ""

    /// Last error encountered, if any. Cleared on `start()`.
    public private(set) var lastError: SpeechCaptureError?

    /// Audio level in [0,1] for waveform visualization. Driven by the
    /// audio engine's input tap.
    public private(set) var audioLevel: Float = 0

    // ── Recognizer plumbing ──────────────────────────────────────────

    private let recognizer: SFSpeechRecognizer?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    @ObservationIgnored
    private var _audioLevelBox: AudioLevelBox?
    @ObservationIgnored
    private var _levelPollTask: Task<Void, Never>?

    public init(locale: Locale = .current) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    // ── Public API ───────────────────────────────────────────────────

    /// Request speech-recognition + microphone authorization. Call once
    /// at app start (or lazily on first mic tap).
    public static func requestAuthorization() async -> Bool {
        // Speech recognition permission.
        let speechStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else { return false }

        // Microphone permission (delegated to the system on capture
        // attempt for macOS; on iOS it needs an explicit ask).
        #if os(iOS)
        return await AVAudioApplication.requestRecordPermission()
        #else
        return true
        #endif
    }

    /// Begin listening. Idempotent — calling while already running stops
    /// the prior session and starts a new one.
    public func start() {
        stop()
        lastError = nil
        transcript = ""

        guard let recognizer, recognizer.isAvailable else {
            lastError = .recognizerUnavailable
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request

        // Configure audio engine input tap.
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Guard: zero-channel format means no mic is available or
        // permission wasn't granted — accessing it crashes AVAudioEngine.
        guard format.channelCount > 0, format.sampleRate > 0 else {
            lastError = .engineStartFailed(
                "No audio input available (channelCount=\(format.channelCount), "
                + "sampleRate=\(format.sampleRate)). Check microphone permission "
                + "in System Settings → Privacy & Security → Microphone."
            )
            return
        }

        inputNode.removeTap(onBus: 0)

        // The tap closure runs on the audio engine's realtime thread —
        // it MUST NOT touch any @MainActor-isolated state. Because this
        // closure is declared inside a @MainActor class, Swift 6.3
        // inherits MainActor isolation onto its body — and the runtime
        // `dispatch_assert_queue` check fires the moment the realtime
        // thread invokes it, crashing the app (EXC_BREAKPOINT in
        // `_swift_task_checkIsolatedSwift`). The `@Sendable` annotation
        // on the typed closure binding defeats that inheritance, and the
        // explicit `[request, levelBox]` capture list keeps the captures
        // Sendable (both already are).
        let levelBox = AudioLevelBox()
        self._audioLevelBox = levelBox

        let tapBlock: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = {
            [request, levelBox] buffer, _ in
            Self.processTapBuffer(buffer, request: request, levelBox: levelBox)
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: tapBlock)

        // Poll audio level from MainActor at ~30Hz
        _levelPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 33_000_000) // ~30fps
                guard let self else { break }
                self.audioLevel = self._audioLevelBox?.load() ?? 0
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            lastError = .engineStartFailed(error.localizedDescription)
            cleanup()
            return
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.cleanup()
                    }
                }
                if let error {
                    // `nsErrorDomain = 1110` ("No speech detected") is
                    // benign — treat as silent stop.
                    let ns = error as NSError
                    if ns.code != 1110 {
                        self.lastError = .recognitionFailed(error.localizedDescription)
                    }
                    self.cleanup()
                }
            }
        }
    }

    /// Stop listening and finalize the transcript. Safe to call when not
    /// running.
    public func stop() {
        request?.endAudio()
        cleanup()
    }

    // ── Internals ────────────────────────────────────────────────────

    /// Realtime-thread audio handler. `nonisolated static` defeats the
    /// MainActor inference that the enclosing class would otherwise apply
    /// — the AVFAudio tap thread can call this directly without tripping
    /// the `dispatch_assert_queue` runtime check.
    nonisolated private static func processTapBuffer(
        _ buffer: AVAudioPCMBuffer,
        request: SFSpeechAudioBufferRecognitionRequest,
        levelBox: AudioLevelBox
    ) {
        request.append(buffer)
        var level: Float = 0
        if let channelData = buffer.floatChannelData?[0] {
            let frames = Int(buffer.frameLength)
            if frames > 0 {
                var sum: Float = 0
                for i in 0..<frames {
                    let s = channelData[i]
                    sum += s * s
                }
                let rms = sqrt(sum / Float(frames))
                level = min(max(rms * 4, 0), 1)
            }
        }
        levelBox.store(level)
    }

    private func cleanup() {
        _levelPollTask?.cancel()
        _levelPollTask = nil
        _audioLevelBox = nil
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        task?.cancel()
        task = nil
        request = nil
        audioLevel = 0
    }


}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Errors
// ═══════════════════════════════════════════════════════════════════

public enum SpeechCaptureError: Error, Sendable, CustomStringConvertible {
    case recognizerUnavailable
    case engineStartFailed(String)
    case recognitionFailed(String)
    case notAuthorized

    public var description: String {
        switch self {
        case .recognizerUnavailable: return "Speech recognizer unavailable for this locale."
        case .engineStartFailed(let m): return "Audio engine couldn't start: \(m)"
        case .recognitionFailed(let m): return "Recognition failed: \(m)"
        case .notAuthorized: return "Speech recognition not authorized in System Settings."
        }
    }
}
