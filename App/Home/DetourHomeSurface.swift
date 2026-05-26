// DetourHomeSurface.swift — ambient native backdrop for Detour home (0.5A)

import SwiftUI

struct DetourHomeSurface: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.015, green: 0.095, blue: 0.083),
                    Color(red: 0.02, green: 0.065, blue: 0.072),
                    Color(red: 0.01, green: 0.028, blue: 0.034),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [
                    Color(red: 0.98, green: 0.65, blue: 0.25).opacity(0.12),
                    .clear,
                ],
                center: .top,
                startRadius: 20,
                endRadius: 420
            )
            RadialGradient(
                colors: [
                    Color(red: 0.18, green: 0.55, blue: 0.48).opacity(0.10),
                    .clear,
                ],
                center: .bottomTrailing,
                startRadius: 40,
                endRadius: 620
            )
            LinearGradient(
                colors: [.clear, .black.opacity(0.34)],
                startPoint: .top,
                endPoint: .bottom
            )
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.12)
        }
        .ignoresSafeArea()
    }
}
