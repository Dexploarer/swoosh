// DetourVoiceEnrollmentRecorder.swift — local microphone enrollment sample recorder (0.5A)

import AVFoundation
import Foundation

@MainActor
final class DetourVoiceEnrollmentRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var hasSample = false
    @Published private(set) var statusText = "Record a short sample when you're ready."

    private var recorder: AVAudioRecorder?
    private var sampleURL: URL?

    func startRecording(to url: URL) async {
        guard !isRecording else { return }

        let granted = await requestMicrophoneAccess()
        guard granted else {
            statusText = "Microphone access is off. You can allow it in System Settings."
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            recorder.record()
            self.recorder = recorder
            sampleURL = url
            hasSample = false
            isRecording = true
            statusText = "Recording. Say the phrase naturally, then stop."
        } catch {
            statusText = "Could not record: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        recorder?.stop()
        isRecording = false

        if let sampleURL, FileManager.default.fileExists(atPath: sampleURL.path(percentEncoded: false)) {
            hasSample = true
            statusText = "Voice sample saved."
        } else {
            hasSample = false
            statusText = "No voice sample was saved."
        }
    }

    func reset() {
        recorder?.stop()
        recorder = nil
        isRecording = false
        hasSample = false
        statusText = "Record a short sample when you're ready."
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            isRecording = false
            hasSample = flag
            statusText = flag ? "Voice sample saved." : "Recording did not finish cleanly."
        }
    }

    private func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}
