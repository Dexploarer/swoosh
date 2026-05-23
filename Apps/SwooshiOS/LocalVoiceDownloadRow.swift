// Apps/SwooshiOS/LocalVoiceDownloadRow.swift — 0.9R On-device voice model UI
//
// Renders download progress + cancel/delete for the active local voice
// model. Reads from a shared `LocalVoiceDownloader` so the executor and
// the UI observe the same `state`.
//
// Two rows: one per catalog entry. Mirrors LocalModelDownloadRow.

import SwiftUI
#if os(iOS)
import SwooshLocalVoice
#endif

struct LocalVoiceDownloadRow: View {
    let model: LocalVoiceModel
    @State private var downloader: LocalVoiceDownloader

    init(model: LocalVoiceModel) {
        self.model = model
        _downloader = State(initialValue: LocalVoiceDownloader(model: model))
    }

    #if os(iOS)
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            statusLine
            controls
            fallbackBanner
        }
        .padding(.vertical, 4)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .frame(width: 22)
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.system(size: 15, weight: .medium))
                Text("\(model.parameters) · \(model.license) · \(model.languageCount == 1 ? "1 language" : "\(model.languageCount) languages")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch downloader.state {
        case .notDownloaded:
            Text("Not downloaded · \(formatBytes(model.estimatedBytes))")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .downloading(progress, written, total):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress).tint(.purple)
                Text("\(Int(progress * 100))% · \(formatBytes(written)) / \(formatBytes(total))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        case let .ready(url):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text("Ready · \(formatBytes(fileSize(url)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case let .failed(reason):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 10) {
            switch downloader.state {
            case .notDownloaded, .failed:
                Button {
                    downloader.download()
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.purple)
            case .downloading:
                Button(role: .destructive) {
                    downloader.cancel()
                } label: {
                    Label("Cancel", systemImage: "stop.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .ready:
                Button(role: .destructive) {
                    downloader.deleteCached()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
    }

    /// Surfaces the truth that today's audio comes from
    /// AVSpeechSynthesizer, not the downloaded weights — until ONNX
    /// Runtime is wired. Honest > magical.
    private var fallbackBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle").font(.caption2)
            Text("Engine fallback active: audio plays via Apple Speech until ONNX Runtime is wired.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func formatBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func fileSize(_ url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return 0 }
        return size
    }
    #else
    var body: some View { EmptyView() }
    #endif
}
