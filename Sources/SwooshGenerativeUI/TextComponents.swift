// SwooshGenerativeUI/TextComponents.swift — Built-in text component views (0.4A)

import SwiftUI

struct UITextView: View {
    let text: String
    let style: UIStyle?

    var body: some View {
        Text(text)
            .font(.system(
                size: CGFloat(style?.fontSize ?? 14),
                weight: resolveFontWeight(style?.fontWeight),
                design: resolveFontDesign(style?.fontDesign)
            ))
            .foregroundStyle(resolveTint(style?.foreground ?? "primary"))
    }
}

struct UIHeadingView: View {
    let text: String
    let level: Int
    let style: UIStyle?

    var body: some View {
        let size: CGFloat = {
            switch level {
            case 1: return 28
            case 2: return 22
            case 3: return 18
            default: return 16
            }
        }()
        Text(text)
            .font(.system(
                size: CGFloat(style?.fontSize ?? Double(size)),
                weight: .bold,
                design: resolveFontDesign(style?.fontDesign)
            ))
            .foregroundStyle(resolveTint(style?.foreground ?? "primary"))
    }
}

struct UICaptionView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct UIMarkdownView: View {
    let text: String

    var body: some View {
        Text(.init(text))
            .font(.system(size: 14))
    }
}

struct UICodeView: View {
    let text: String
    let language: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(10)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel(language.map { "Code block: \($0)" } ?? "Code block")
    }
}
