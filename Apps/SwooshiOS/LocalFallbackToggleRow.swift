// Apps/SwooshiOS/LocalFallbackToggleRow.swift — Local-model fallback toggle
//
// When the user is offline or the Mac daemon is unreachable, route the
// chat to the on-device LiteRT model (Gemma 4 E4B by default).
// The toggle lives in Settings → Local model.

import SwiftUI
#if os(iOS)
import SwooshLocalLLM
#endif

struct LocalFallbackToggleRow: View {
    @Environment(ClientSession.self) private var session
    @State private var enabled: Bool = UserDefaults.standard.object(forKey: "swoosh.localFallback") as? Bool ?? true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $enabled) {
                HStack(spacing: 10) {
                    Image(systemName: "memorychip")
                        .frame(width: 22)
                        .foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use local model when offline")
                            .font(.system(size: 15, weight: .medium))
                        Text(footnote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onChange(of: enabled) { _, newValue in
                session.localFallbackEnabled = newValue
                #if os(iOS)
                // Toggle-on prewarm: start the model download as soon as
                // the user opts in, so the first fallback isn't blocked
                // on a multi-GB download.
                if newValue, !session.localModelDownloader.isCached {
                    session.localModelDownloader.download()
                }
                #endif
            }
        }
    }

    private var footnote: String {
        #if os(iOS)
        return "Falls back to \(session.localModel.displayName) (~\(ByteCountFormatter.string(fromByteCount: session.localModel.estimatedBytes, countStyle: .file))) when the Mac daemon is unreachable."
        #else
        return "iOS only."
        #endif
    }
}
