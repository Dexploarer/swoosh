// SwooshUI/AppleIntelligence/AppleIntelligenceHooks.swift — WritingTools & Image Playground (0.4A)
//
// Wires Apple Intelligence surfaces that are first-class on macOS 26 / iOS
// 26:
//
//   • WritingTools — Cmd-click in any chat composer brings up
//     Proofread / Rewrite / Friendly / Concise / Summary.
//   • Image Playground — agent-produced image prompts hand off to the
//     Image Playground sheet for the user to refine before saving.
//   • Genmoji — TextField gains the standard "+ Add Genmoji" entry point
//     automatically when WritingTools is enabled.
//
// macOS 14 / iOS 17 callers still compile — features that aren't available
// degrade to plain TextField / TextEditor with no AI affordance.

import SwiftUI
#if canImport(ImagePlayground)
import ImagePlayground
#endif

// MARK: - Composer that hosts WritingTools

public struct SwooshAIComposer: View {
    @Binding public var text: String
    public let placeholder: String
    public let onSubmit: () -> Void

    @FocusState private var focused: Bool

    public init(
        text: Binding<String>,
        placeholder: String = "Ask Swoosh anything…",
        onSubmit: @escaping () -> Void
    ) {
        self._text = text
        self.placeholder = placeholder
        self.onSubmit = onSubmit
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .focused($focused)
                .lineLimit(1...8)
                .onSubmit(onSubmit)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .modifier(SwooshWritingToolsModifier())

            Button(action: onSubmit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Wraps `.writingToolsBehavior(.complete)` when available, so the composer
/// surfaces Proofread / Rewrite / Friendly / Concise / Summary natively.
struct SwooshWritingToolsModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.2, iOS 18.2, *) {
            content.writingToolsBehavior(.complete)
        } else {
            content
        }
    }
}

// MARK: - Image Playground sheet

public struct SwooshImagePlaygroundButton: View {
    @State private var isPresented = false
    public let initialPrompt: String?
    public let onImage: (URL) -> Void

    public init(initialPrompt: String? = nil, onImage: @escaping (URL) -> Void) {
        self.initialPrompt = initialPrompt
        self.onImage = onImage
    }

    public var body: some View {
        Button {
            isPresented = true
        } label: {
            Label("Generate Image", systemImage: "sparkles.tv")
        }
        .modifier(SwooshImagePlaygroundSheetModifier(
            isPresented: $isPresented,
            initialPrompt: initialPrompt,
            onImage: onImage
        ))
    }
}

struct SwooshImagePlaygroundSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let initialPrompt: String?
    let onImage: (URL) -> Void

    func body(content: Content) -> some View {
        #if canImport(ImagePlayground)
        if #available(macOS 15.2, iOS 18.2, *) {
            content.imagePlaygroundSheet(
                isPresented: $isPresented,
                concepts: initialPrompt.map { [ImagePlaygroundConcept.text($0)] } ?? []
            ) { url in
                onImage(url)
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

// MARK: - Genmoji entry point

/// Encourage the user to tap-hold the keyboard to insert a Genmoji.
/// macOS surfaces these through the system character viewer; this stub is
/// here so call sites have a single label they can render alongside
/// composer affordances.
public struct SwooshGenmojiHintView: View {
    public init() {}
    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "face.smiling.inverse")
                .font(.system(size: 11))
            Text("Tap & hold to add a Genmoji")
                .font(.system(size: 10))
        }
        .foregroundStyle(.tertiary)
    }
}
