// DetourIntegrationConnectionCard.swift — app connection tile (0.5A)

import SwiftUI

struct DetourIntegrationConnectionCard: View {
    let item: DetourIntegrationConnection
    let connect: () -> Void
    let test: () -> Void
    let setScope: (DetourDelegationRole) -> Void
    let isBusy: Bool
    let feedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                logo
                Spacer()
                stateDot
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.integration.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(item.detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if item.selected {
                scopeControl
            }
            Button(buttonTitle) {
                if item.selected && item.canConnectDirectly {
                    test()
                } else {
                    connect()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isBusy)
        }
        .padding(14)
        .frame(minHeight: 150, alignment: .topLeading)
        .background(.white.opacity(backgroundOpacity), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(stateColor.opacity(item.selected ? 0.48 : 0.18), lineWidth: 1)
        }
    }

    private var logo: some View {
        AsyncImage(url: item.integration.logoURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .padding(5)
            default:
                Text(initials)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 36, height: 36)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var stateDot: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(stateColor)
                .frame(width: 7, height: 7)
            Text(item.state.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(stateColor)
        }
    }

    private var scopeControl: some View {
        HStack(spacing: 6) {
            scopeButton("Me", .user)
            scopeButton("Agent", .agent)
        }
    }

    private func scopeButton(_ title: String, _ role: DetourDelegationRole) -> some View {
        Button(title) {
            setScope(role)
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(item.scope == role ? stateColor.opacity(0.24) : .white.opacity(0.08), in: Capsule())
    }

    private var initials: String {
        item.integration.name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }

    private var backgroundOpacity: Double {
        item.selected ? 0.11 : 0.055
    }

    private var stateColor: Color {
        switch item.state {
        case .verified:
            return .green
        case .selected:
            return .blue
        case .needsSetup:
            return .orange
        case .detected:
            return Color(red: 0.9, green: 0.72, blue: 0.32)
        case .available:
            return .white.opacity(0.48)
        }
    }

    private var buttonTitle: String {
        if let feedback { return feedback }
        if isBusy { return item.canConnectDirectly ? "Checking..." : "Opening..." }
        if item.selected { return item.canConnectDirectly ? "Test" : "Configure" }
        return item.canConnectDirectly ? "Connect" : "Configure"
    }
}
