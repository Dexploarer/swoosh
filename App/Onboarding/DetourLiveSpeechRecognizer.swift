// DetourLiveSpeechRecognizer.swift — live local dictation for macOS onboarding (0.5A)

import AVFoundation
import Foundation
import OSLog
import Speech

private let detourLiveSpeechLog = Logger(subsystem: "ai.swoosh.detour.mac", category: "LiveSpeech")

@MainActor
final class DetourLiveSpeechRecognizer: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""
    @Published private(set) var finalTranscript = ""
    @Published private(set) var authorizationState: AuthorizationState = .notDetermined

    enum AuthorizationState: Equatable, Sendable {
        case notDetermined
        case authorized
        case denied
        case restricted
    }

    var onTranscript: ((String) -> Void)?
    var onFinalTranscript: ((String) -> Void)?

    private var audioEngine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var analyzerInput: AsyncStream<AnalyzerInput>.Continuation?
    private var resultTask: Task<Void, Never>?
    private var hasCapturedAudio = false

    func requestAuthorization() async -> AuthorizationState {
        let state: AuthorizationState
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            state = .authorized
        case .denied:
            state = .denied
        case .restricted:
            state = .restricted
        case .notDetermined:
            state = await AVCaptureDevice.requestAccess(for: .audio) ? .authorized : .denied
        @unknown default:
            state = .restricted
        }
        authorizationState = state
        return state
    }

    func start(locale: Locale = .current) async throws {
        guard !isListening else { return }
        guard await requestAuthorization() == .authorized else {
            detourLiveSpeechLog.error("[DetourLiveSpeechRecognizer] microphone authorization failed")
            throw DetourLiveSpeechRecognizerError.notAuthorized
        }

        stopCapture(finishAnalysis: false, publishTranscript: false)

        let selectedLocale = try await Self.supportedLocale(for: locale)
        let transcriber = SpeechTranscriber(
            locale: selectedLocale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        try await Self.ensureModel(for: transcriber, locale: selectedLocale)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw DetourLiveSpeechRecognizerError.recognizerUnavailable
        }

        let (inputSequence, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        resultTask = Task { [weak self, transcriber] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    await MainActor.run {
                        guard let self, !text.isEmpty else { return }
                        self.transcript = text
                        self.onTranscript?(text)
                        if result.isFinal {
                            self.finalTranscript = text
                            self.onFinalTranscript?(text)
                        }
                    }
                }
            } catch {
                detourLiveSpeechLog.error("[DetourLiveSpeechRecognizer] result stream failed error=\(error.localizedDescription, privacy: .public)")
            }
        }

        try await analyzer.start(inputSequence: inputSequence)
        do {
            try startAudioEngine(analyzerFormat: analyzerFormat, inputContinuation: inputContinuation)
        } catch {
            detourLiveSpeechLog.error("[DetourLiveSpeechRecognizer] audio engine start failed error=\(error.localizedDescription, privacy: .public)")
            await analyzer.cancelAndFinishNow()
            resultTask?.cancel()
            resultTask = nil
            throw error
        }

        self.analyzer = analyzer
        self.transcriber = transcriber
        analyzerInput = inputContinuation
        transcript = ""
        finalTranscript = ""
        hasCapturedAudio = false
        isListening = true
        detourLiveSpeechLog.info("[DetourLiveSpeechRecognizer] live speech capture started locale=\(selectedLocale.identifier(.bcp47), privacy: .public) sampleRate=\(analyzerFormat.sampleRate, privacy: .public)")
    }

    func stop() {
        stopCapture(finishAnalysis: true, publishTranscript: true)
    }

    func cancel() {
        stopCapture(finishAnalysis: false, publishTranscript: false)
        transcript = ""
    }

    private func startAudioEngine(
        analyzerFormat: AVAudioFormat,
        inputContinuation: AsyncStream<AnalyzerInput>.Continuation
    ) throws {
        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0 else {
            throw DetourLiveSpeechRecognizerError.inputUnavailable
        }
        let inputSampleRate = inputFormat.sampleRate
        let inputChannelCount = inputFormat.channelCount

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(
            onBus: 0,
            bufferSize: 4_096,
            format: inputFormat,
            block: Self.makeAudioTap(
                analyzerFormat: analyzerFormat,
                inputContinuation: inputContinuation,
                inputSampleRate: inputSampleRate,
                inputChannelCount: inputChannelCount,
                recognizer: self
            )
        )

        audioEngine.prepare()
        try audioEngine.start()
        self.audioEngine = audioEngine
    }

    private nonisolated static func makeAudioTap(
        analyzerFormat: AVAudioFormat,
        inputContinuation: AsyncStream<AnalyzerInput>.Continuation,
        inputSampleRate: Double,
        inputChannelCount: AVAudioChannelCount,
        recognizer: DetourLiveSpeechRecognizer
    ) -> AVAudioNodeTapBlock {
        { [weak recognizer] buffer, _ in
            do {
                let converted = try Self.convert(buffer, to: analyzerFormat)
                inputContinuation.yield(AnalyzerInput(buffer: converted))
                Task { @MainActor in
                    guard let recognizer else { return }
                    if !recognizer.hasCapturedAudio {
                        detourLiveSpeechLog.info("[DetourLiveSpeechRecognizer] first audio buffer captured sampleRate=\(inputSampleRate, privacy: .public) channels=\(inputChannelCount, privacy: .public)")
                    }
                    recognizer.hasCapturedAudio = true
                }
            } catch {
                detourLiveSpeechLog.error("[DetourLiveSpeechRecognizer] audio buffer conversion failed error=\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func stopCapture(finishAnalysis: Bool, publishTranscript: Bool) {
        let pendingTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        analyzerInput?.finish()
        analyzerInput = nil

        if finishAnalysis {
            let analyzer = analyzer
            Task {
                try? await analyzer?.finalizeAndFinishThroughEndOfInput()
            }
        } else {
            let analyzer = analyzer
            Task {
                await analyzer?.cancelAndFinishNow()
            }
        }

        analyzer = nil
        transcriber = nil
        resultTask?.cancel()
        resultTask = nil
        isListening = false
        hasCapturedAudio = false

        if publishTranscript, !pendingTranscript.isEmpty {
            finalTranscript = pendingTranscript
            onFinalTranscript?(pendingTranscript)
        }
    }

    private static func supportedLocale(for locale: Locale) async throws -> Locale {
        if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return supported
        }
        if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en_US")) {
            return supported
        }
        throw DetourLiveSpeechRecognizerError.localeUnsupported
    }

    private static func ensureModel(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        let installed = await SpeechTranscriber.installedLocales
            .map { $0.identifier(.bcp47) }
            .contains(locale.identifier(.bcp47))
        guard !installed else { return }

        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await downloader.downloadAndInstall()
        }
    }

    private nonisolated static func convert(
        _ buffer: AVAudioPCMBuffer,
        to format: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        if buffer.format == format {
            return buffer
        }

        guard let converter = AVAudioConverter(from: buffer.format, to: format) else {
            throw DetourLiveSpeechRecognizerError.inputUnavailable
        }

        converter.primeMethod = .none
        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = max(1, AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)))
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else {
            throw DetourLiveSpeechRecognizerError.inputUnavailable
        }

        let source = DetourSpeechBufferConversionSource(buffer)
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            source.next(status: inputStatus)
        }

        if let conversionError {
            throw conversionError
        }
        if status == .error {
            throw DetourLiveSpeechRecognizerError.inputUnavailable
        }
        return output
    }
}

private final class DetourSpeechBufferConversionSource: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard let buffer else {
            status.pointee = .noDataNow
            return nil
        }
        self.buffer = nil
        status.pointee = .haveData
        return buffer
    }
}

enum DetourLiveSpeechRecognizerError: LocalizedError, Sendable {
    case notAuthorized
    case recognizerUnavailable
    case inputUnavailable
    case localeUnsupported

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            "Microphone access is required."
        case .recognizerUnavailable:
            "Speech recognition is unavailable."
        case .inputUnavailable:
            "Audio input is unavailable."
        case .localeUnsupported:
            "Speech recognition is unavailable for this language."
        }
    }
}
