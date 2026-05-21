// Apps/SwooshiOS/LocalFallbackToggleRow.swift — Local-model fallback toggle
//
// When the user is offline or the Mac daemon is unreachable, route the
// chat to the on-device LiteRT model (Gemma 3n E2B Int4 by default).
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
            }
        }
    }

    private var footnote: String {
        #if os(iOS)
        return "Falls back to Gemma 3n E2B (~1.3 GB) when the Mac daemon is unreachable."
        #else
        return "iOS only."
        #endif
    }
}
