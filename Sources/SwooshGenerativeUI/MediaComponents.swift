// SwooshGenerativeUI/MediaComponents.swift — Built-in media component views (0.4A)

import SwiftUI

struct UIImageView: View {
    let systemName: String?
    let url: String?
    let size: Double?
    let accessibilityLabel: String?
    let placeholderShape: UIImagePlaceholderShape

    init(
        systemName: String?,
        url: String?,
        size: Double?,
        accessibilityLabel: String? = nil,
        placeholderShape: UIImagePlaceholderShape = .roundedRectangle
    ) {
        self.systemName = systemName
        self.url = url
        self.size = size
        self.accessibilityLabel = accessibilityLabel
        self.placeholderShape = placeholderShape
    }

    var body: some View {
        let dimension = CGFloat(size ?? 24)
        if let systemName {
            Image(systemName: systemName)
                .resizable()
                .scaledToFit()
                .frame(width: dimension, height: dimension)
                .accessibilityLabel(accessibilityLabel ?? imageLabel(forSystemName: systemName))
        } else if let url, let parsed = URL(string: url) {
            AsyncImage(url: parsed) { phase in
                switch phase {
                case .empty:
                    imagePlaceholder(shape: placeholderShape)
                        .accessibilityLabel(accessibilityLabel ?? "Loading image")
                case let .success(image):
                    image.resizable().scaledToFit()
                        .accessibilityLabel(accessibilityLabel ?? "Loaded image")
                case .failure:
                    Image(systemName: "exclamationmark.triangle")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(accessibilityLabel ?? "Image failed to load")
                @unknown default:
                    imagePlaceholder(shape: placeholderShape)
                        .accessibilityLabel(accessibilityLabel ?? "Placeholder image")
                }
            }
            .frame(width: dimension, height: dimension)
        } else {
            Image(systemName: "photo")
                .resizable()
                .scaledToFit()
                .frame(width: dimension, height: dimension)
                .accessibilityLabel(accessibilityLabel ?? "Placeholder image")
        }
    }
}

enum UIImagePlaceholderShape: Sendable {
    case roundedRectangle
    case circle
}

@ViewBuilder
func imagePlaceholder(shape: UIImagePlaceholderShape) -> some View {
    switch shape {
    case .roundedRectangle:
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.secondary.opacity(0.2))
    case .circle:
        Circle()
            .fill(Color.secondary.opacity(0.2))
    }
}

func imageLabel(forSystemName systemName: String) -> String {
    systemName
        .replacingOccurrences(of: ".", with: " ")
        .replacingOccurrences(of: "_", with: " ")
}

struct UIAvatarView: View {
    let systemName: String?
    let url: String?
    let label: String?

    var body: some View {
        HStack(spacing: 8) {
            UIImageView(
                systemName: systemName,
                url: url,
                size: 28,
                accessibilityLabel: label,
                placeholderShape: .circle
            )
                .clipShape(Circle())
            if let label {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
        }
    }
}
