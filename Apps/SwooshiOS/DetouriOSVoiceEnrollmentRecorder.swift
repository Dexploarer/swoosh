// DetouriOSVoiceEnrollmentRecorder.swift — local voice sample capture for iPhone onboarding (0.5A)

import AVFoundation
import Foundation

@MainActor
final class DetouriOSVoiceEnrollmentRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var hasRecording = false
    @Published private(set) var statusText = "Ready."

    private var audioRecorder: AVAudioRecorder?
    private var currentSampleURL: URL?

    func toggleRecording(sampleURL: URL) async {
        if isRecording {
            stopRecording()
            return
        }

        do {
            try await startRecording(sampleURL: sampleURL)
        } catch {
            statusText = error.localizedDescription
            isRecording = false
        }
    }

    func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        hasRecording = currentSampleURL.map(Self.hasRecordedAudio(at:)) ?? false
        statusText = hasRecording ? "Saved." : "Ready."
        deactivateSession()
    }

    func fail(_ message: String) {
        audioRecorder?.stop()
        audioRecorder = nil
        statusText = message
        isRecording = false
        deactivateSession()
    }

    private func startRecording(sampleURL: URL) async throws {
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        guard granted else {
            throw DetouriOSVoiceEnrollmentError.microphoneDenied
        }

        try FileManager.default.createDirectory(
            at: sampleURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: sampleURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: sampleURL)
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setPreferredSampleRate(16_000)
        try session.setActive(true)

        let recorder = try AVAudioRecorder(url: sampleURL, settings: settings)
        guard recorder.prepareToRecord(), recorder.record() else {
            throw DetouriOSVoiceEnrollmentError.recordingFailed
        }

        audioRecorder = recorder
        currentSampleURL = sampleURL
        isRecording = true
        hasRecording = false
        statusText = "Recording."
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private nonisolated static func hasRecordedAudio(at url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)),
              let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.intValue > 0
    }
}

enum DetouriOSVoiceEnrollmentError: LocalizedError {
    case microphoneDenied
    case recordingFailed

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Microphone access is required to save a voice sample."
        case .recordingFailed:
            "The voice sample could not start recording."
        }
    }
}
