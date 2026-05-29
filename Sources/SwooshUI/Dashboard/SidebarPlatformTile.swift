// SwooshUI/Dashboard/SidebarPlatformTile.swift — Gaming sidebar platform tile — 0.9Y
//
// Extracted from DashboardView to keep that file under the LOC ceiling.
// A hover/toggle tile used in the contextual gaming sidebar grid.

#if os(macOS)

import SwiftUI
import SwooshGenerativeUI

struct SidebarPlatformTile: View {
    let name: String
    let iconOn: String
    let iconOff: String
    let accent: Color
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                let showOn = isSelected || isHovered
                let imgName = showOn ? iconOn : iconOff
                if let url = Bundle.module.url(forResource: imgName, withExtension: "png", subdirectory: "GamingIcons"),
                   let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                } else if let url = Bundle.main.url(forResource: imgName, withExtension: "png", subdirectory: "GamingIcons"),
                          let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: imgName.contains("localwindow") ? "desktopcomputer" : "gamecontroller")
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected ? accent : isHovered ? accent.opacity(0.7) : VoltPaper.foreground.opacity(0.35))
                        .frame(width: 28, height: 28)
                }

                Text(name)
                    .font(.system(size: 8, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? accent : isHovered ? accent.opacity(0.7) : VoltPaper.foreground.opacity(0.4))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.1) : isHovered ? accent.opacity(0.05) : Color.clear)
            )
            .shadow(color: isSelected ? accent.opacity(0.5) : isHovered ? accent.opacity(0.3) : .clear, radius: 8)
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = h }
        }
    }
}

#endif
