// Apps/SwooshiOS/LocalModelDownloadRow.swift — 0.9R Settings download UI for
// the on-device LiteRT model. Lives directly under the fallback toggle.
// Reads the shared `LiteRTModelDownloader` from `ClientSession` so the
// fallback executor and the UI see the same `state`.

import SwiftUI
#if os(iOS)
import SwooshLocalLLM
#endif

struct LocalModelDownloadRow: View {
    @Environment(ClientSession.self) private var session

    #if os(iOS)
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            statusLine
            controls
        }
        .padding(.vertical, 4)
    }

    private var downloader: LiteRTModelDownloader { session.localModelDownloader }
    private var model: LiteRTModel { session.localModel }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "internaldrive")
                .frame(width: 22)
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.system(size: 15, weight: .medium))
                Text(LiteRTDevicePolicy.explainSelection(model))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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
                ProgressView(value: progress)
                    .tint(.cyan)
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
