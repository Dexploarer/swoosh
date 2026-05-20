// Apps/SwooshiOS/IconTile.swift — Tinted rounded icon tile
//
// Reusable visual unit used across SettingsScreen and ConnectionsScreen
// rows. A small rounded square in a chain-or-feature-specific tint with a
// centered SF Symbol glyph. Matches the mobile-app convention of icon
// tiles in sectioned lists.

import SwiftUI

struct IconTile: View {
    let systemName: String
    let tint: Color
    var size: CGFloat = 30
    var cornerRadius: CGFloat = 8

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(tint.gradient)
            Image(systemName: systemName)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

struct InitialsTile: View {
    let text: String
    let background: Color
    let foreground: Color
    var size: CGFloat = 30
    var cornerRadius: CGFloat = 8

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(background)
            Text(text)
                .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
                .foregroundStyle(foreground)
        }
        .frame(width: size, height: size)
    }
}
