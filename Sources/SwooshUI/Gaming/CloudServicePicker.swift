#if os(macOS)

// SwooshUI/Gaming/CloudServicePicker.swift — Platform selector with real icons
//
// Each platform is a square tile showing its brand icon. Tapping a tile
// "lights it up" — the icon switches from a dark/off state to a vivid/on
// state with a brand-colored glow halo. Native sources auto-install their
// companion app (Chiaki, Greenlight, Steam Link) on first selection.
// 0.9T – May 2026

import SwiftUI
import SwooshCloudGaming

// ═══════════════════════════════════════════════════════════════════
// MARK: - CloudServicePicker
// ═══════════════════════════════════════════════════════════════════

public struct CloudServicePicker: View {
    @Binding public var selectedSource: GameSource?
    @State private var hoveredID: String?
    @State private var installingSource: String?

    public init(selectedSource: Binding<GameSource?>) {
        _selectedSource = selectedSource
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(CloudGamingService.allCases) { service in
                    PlatformTile(
                        title: service.displayName,
                        iconOnName: service.iconAssetOn,
                        iconOffName: service.iconAssetOff,
                        accentColor: Color(hex: service.accentHex),
                        isSelected: isSelectedWeb(service),
                        isHovered: hoveredID == service.id,
                        isInstalling: false
                    )
                    .onTapGesture { selectedSource = .web(service) }
                    .onHover { h in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            hoveredID = h ? service.id : nil
                        }
                    }
                }

                ForEach(NativeGameSource.allCases) { source in
                    PlatformTile(
                        title: source.displayName,
                        iconOnName: source.iconAssetOn,
                        iconOffName: source.iconAssetOff,
                        accentColor: source.brandColor,
                        isSelected: isSelectedNative(source),
                        isHovered: hoveredID == source.id,
                        isInstalling: installingSource == source.id
                    )
                    .onTapGesture {
                        selectedSource = .native(source)
                        ensureInstalled(source)
                    }
                    .onHover { h in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            hoveredID = h ? source.id : nil
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // ── Selection helpers ─────────────────────────────────────────

    private func isSelectedWeb(_ service: CloudGamingService) -> Bool {
        guard case .web(let s) = selectedSource else { return false }
        return s == service
    }

    private func isSelectedNative(_ source: NativeGameSource) -> Bool {
        guard case .native(let s) = selectedSource else { return false }
        return s == source
    }

    // ── Auto-install ─────────────────────────────────────────────

    private func ensureInstalled(_ source: NativeGameSource) {
        guard source != .localWindow else { return }

        Task {
            // Check if app is already installed
            let bundleIDs = source.bundleIdentifiers
            let installed = bundleIDs.contains { bid in
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) != nil
            }
            guard !installed else { return }

            await MainActor.run { installingSource = source.id }

            let command = source.installCommand
            guard !command.isEmpty else { return }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            try? process.run()
            process.waitUntilExit()

            await MainActor.run { installingSource = nil }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - PlatformTile
// ═══════════════════════════════════════════════════════════════════

private struct PlatformTile: View {
    let title: String
    let iconOnName: String
    let iconOffName: String
    let accentColor: Color
    let isSelected: Bool
    let isHovered: Bool
    let isInstalling: Bool

    private let iconSize: CGFloat = 36

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                if isInstalling {
                    ProgressView()
                        .controlSize(.small)
                        .tint(accentColor)
                        .frame(width: iconSize, height: iconSize)
                } else {
                    platformIcon
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSize, height: iconSize)
                }
            }
            .shadow(color: isSelected ? accentColor.opacity(0.7) : .clear, radius: 10)

            Text(title)
                .font(.system(size: 9, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? accentColor : Color.white.opacity(0.45))
                .lineLimit(1)
                .frame(width: iconSize + 20)
        }
        .opacity(isSelected ? 1.0 : isHovered ? 0.8 : 0.55)
        .scaleEffect(isSelected ? 1.1 : isHovered ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
    }

    @ViewBuilder
    private var platformIcon: some View {
        let name = isSelected ? iconOnName : iconOffName
        if let nsImage = Self.loadIcon(named: name) {
            Image(nsImage: nsImage)
                .resizable()
        } else {
            Image(systemName: "gamecontroller.fill")
                .resizable()
        }
    }

    private static func loadIcon(named name: String) -> NSImage? {
        // SwiftPM resource bundle
        if let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "GamingIcons"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        // Main bundle fallback (Xcode build)
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "GamingIcons"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return nil
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Icon asset names
// ═══════════════════════════════════════════════════════════════════

extension CloudGamingService {
    var iconAssetOn: String {
        switch self {
        case .xboxCloud:   "xbox_on"
        case .geforceNow:  "geforce_on"
        case .amazonLuna:  "luna_on"
        case .boosteroid:  "boosteroid_on"
        }
    }

    var iconAssetOff: String {
        switch self {
        case .xboxCloud:   "xbox_off"
        case .geforceNow:  "geforce_off"
        case .amazonLuna:  "luna_off"
        case .boosteroid:  "boosteroid_off"
        }
    }
}

extension NativeGameSource {
    var iconAssetOn: String {
        switch self {
        case .greenlight:   "xbox_on"        // Greenlight is Xbox streaming
        case .steamLink:    "steam_on"
        case .playstation:  "playstation_on"
        case .localWindow:  "localwindow_on"
        }
    }

    var iconAssetOff: String {
        switch self {
        case .greenlight:   "xbox_off"
        case .steamLink:    "steam_off"
        case .playstation:  "playstation_off"
        case .localWindow:  "localwindow_off"
        }
    }

    var brandColor: Color {
        switch self {
        case .greenlight:   Color(hex: "#107C10")  // Xbox green
        case .steamLink:    Color(hex: "#1B2838")  // Steam dark blue
        case .playstation:  Color(hex: "#006FCD")  // PlayStation blue
        case .localWindow:  .cyan
        }
    }

    /// Shell command to auto-install the native app.
    var installCommand: String {
        switch self {
        case .playstation:  "brew install --cask chiaki 2>/dev/null || open https://www.playstation.com/remote-play/"
        case .greenlight:   "brew install --cask greenlight 2>/dev/null || open https://github.com/nicovs/greenlight/releases"
        case .steamLink:    "open macappstore://apps.apple.com/app/steam-link/id1246969117"
        case .localWindow:  ""
        }
    }
}

#endif
