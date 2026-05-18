// SwooshUI/Themes/AppearanceEditor.swift — Visual theme editor (0.4A)
//
// Three-column editor: preset gallery (left), live preview (center), tabbed
// controls (right). Every change updates the live ThemeManager so downstream
// surfaces — popover, toolbar, widgets — re-render immediately. Save persists
// to `~/.swoosh/theme.json` with a sensory-feedback confirmation.

import SwiftUI
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public struct AppearanceEditorView: View {
    @Bindable var manager: ThemeManager
    @State private var selectedSection: ControlSection = .colors
    @State private var saveTick: Int = 0
    @State private var importError: String?

    enum ControlSection: String, CaseIterable, Identifiable {
        case colors, glass, layout, typography, animations, background
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .colors:     return "Colors"
            case .glass:      return "Glass"
            case .layout:     return "Layout"
            case .typography: return "Type"
            case .animations: return "Motion"
            case .background: return "Background"
            }
        }
        var icon: String {
            switch self {
            case .colors:     return "paintpalette.fill"
            case .glass:      return "circle.hexagongrid.fill"
            case .layout:     return "square.grid.3x3.square"
            case .typography: return "textformat.size"
            case .animations: return "waveform.path.ecg"
            case .background: return "rectangle.fill.on.rectangle.fill"
            }
        }
    }

    public init(manager: ThemeManager) {
        self.manager = manager
    }

    public var body: some View {
        HStack(spacing: 0) {
            presetRail
                .frame(width: 240)
                .background(.regularMaterial)

            Divider()

            previewColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            controlsRail
                .frame(width: 340)
                .background(.regularMaterial)
        }
        .swooshThemedBackground()
        .swooshFeedback(.success, on: saveTick)
        .navigationTitle("Appearance")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    do {
                        try manager.save(to: ThemeManager.defaultURL)
                        saveTick &+= 1
                    } catch {
                        importError = "Save failed: \(error.localizedDescription)"
                    }
                } label: {
                    Label("Save", systemImage: "checkmark.circle.fill")
                        .swooshBounceOnChange(saveTick)
                }

                Button(role: .destructive) {
                    manager.update(with: .liquidGlassDefault)
                } label: {
                    Label("Reset", systemImage: "arrow.uturn.backward.circle")
                }
            }
        }
        .alert("Import error",
               isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: - Preset rail

    private var presetRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.tint)
                    .swooshBreathe()
                Text("Presets")
                    .font(.headline)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(SwooshThemeConfig.builtInPresets) { preset in
                        PresetRow(
                            preset: preset,
                            isActive: manager.config.name == preset.config.name,
                            onSelect: {
                                withAnimation(.smooth) {
                                    manager.update(with: preset.config)
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }

            Divider()

            // File actions footer
            VStack(alignment: .leading, spacing: 6) {
                Text("Theme File")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("~/.swoosh/theme.json")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
                HStack {
                    Button {
                        manager.load(from: ThemeManager.defaultURL)
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    Button {
                        Self.revealInFinder(ThemeManager.defaultURL)
                    } label: {
                        Label("Reveal", systemImage: "folder")
                    }
                    .controlSize(.small)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Preview column

    private var previewColumn: some View {
        VStack(spacing: 20) {
            ThemePreviewCard()
                .frame(maxWidth: 520)
                .padding(.top, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }

    // MARK: - Controls rail

    private var controlsRail: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedSection) {
                ForEach(ControlSection.allCases) { section in
                    Image(systemName: section.icon).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()

            ScrollView {
                Group {
                    switch selectedSection {
                    case .colors:     ColorsControls(config: $manager.config)
                    case .glass:      GlassControls(config: $manager.config)
                    case .layout:     LayoutControls(config: $manager.config)
                    case .typography: TypographyControls(config: $manager.config)
                    case .animations: AnimationsControls(config: $manager.config)
                    case .background: BackgroundControls(config: $manager.config)
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Reveal helper

    static func revealInFinder(_ url: URL) {
        #if os(macOS)
        // NSWorkspace lookup is intentionally string-based to keep this file
        // free of AppKit imports — the editor is shared with iOS.
        let selector = NSSelectorFromString("sharedWorkspace")
        guard let wsClass = NSClassFromString("NSWorkspace") as? NSObject.Type,
              let workspace = wsClass.perform(selector)?.takeUnretainedValue()
        else { return }
        let act = NSSelectorFromString("activateFileViewerSelectingURLs:")
        _ = (workspace as AnyObject).perform(act, with: [url])
        #endif
    }
}

// MARK: - Preset row

private struct PresetRow: View {
    let preset: SwooshThemePreset
    let isActive: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                presetSwatch
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.displayName)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(preset.tagline)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(hex: preset.config.colors.accent))
                        .swooshBounceOnChange(isActive)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive
                          ? Color(hex: preset.config.colors.accent).opacity(0.12)
                          : (isHovered ? Color.secondary.opacity(0.08) : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isActive
                                  ? Color(hex: preset.config.colors.accent).opacity(0.35)
                                  : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var presetSwatch: some View {
        if #available(macOS 15.0, iOS 18.0, *), preset.config.background.kind != "solid" {
            MeshGradient(
                width: 3,
                height: 3,
                points: SwooshTheme(from: preset.config).backgroundMeshPoints,
                colors: SwooshTheme(from: preset.config).backgroundMeshColors
            )
        } else {
            LinearGradient(
                colors: [
                    Color(hex: preset.config.colors.background),
                    Color(hex: preset.config.colors.surface),
                    Color(hex: preset.config.colors.accent),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Preview card

private struct ThemePreviewCard: View {
    @Environment(\.swooshTheme) var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .swooshBreathe()
                Text(theme.config.name)
                    .font(theme.headlineFont)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Text("Live preview")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
            }

            Text("Approved memories surface here, drawn through the active theme. Glass, type, and motion update as you tune the controls on the right.")
                .font(theme.bodyFont)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                statusChip("Healthy", systemImage: "checkmark.seal.fill", tint: theme.success)
                statusChip("3 pending", systemImage: "hand.raised.fill", tint: theme.warning)
                statusChip("12 cards", systemImage: "rectangle.3.group.fill", tint: theme.info)
            }

            HStack(spacing: 10) {
                Button {} label: {
                    Label("Run workflow", systemImage: "play.fill")
                }
                .buttonStyle(.glass)

                Button {} label: {
                    Label("New chat", systemImage: "bubble.left.and.bubble.right")
                }
                .buttonStyle(.glass)

                Spacer()

                Image(systemName: "circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.success)
                    .swooshPulse()
                Text("Provider connected")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .padding(theme.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface.opacity(0.5))
        .swooshGlass()
        .animation(theme.springAnimation, value: theme.config.name)
    }

    private func statusChip(_ title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(tint.opacity(0.16))
        )
    }
}
