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
import Speech

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
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            self?.updateAudioLevel(from: buffer)
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

    private func cleanup() {
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        task?.cancel()
        task = nil
        request = nil
        audioLevel = 0
    }

    private func updateAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        // RMS amplitude → [0,1].
        var sum: Float = 0
        for i in 0..<frames {
            let s = channelData[i]
            sum += s * s
        }
        let rms = sqrt(sum / Float(frames))
        // Clamp + perceptual scale.
        let level = min(max(rms * 4, 0), 1)
        Task { @MainActor in
            self.audioLevel = level
        }
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
