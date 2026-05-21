// SwooshUI/MenuBar/MenuBarCustomizerView.swift — Full customization UI
//
// Gives the user complete control over their menu bar layout:
// - Preset picker with live preview
// - Drag-to-reorder sections
// - Per-section toggles, title overrides, icon overrides
// - Card style, icon mode, dimensions
// - Export/import JSON config

import SwiftUI
import SwooshSecrets

public struct MenuBarCustomizerView: View {
    @Bindable var manager: MenuBarManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.swooshTheme) var theme

    @State private var selectedTab: CustomizerTab = .presets

    enum CustomizerTab: Hashable {
        case presets, sections, appearance, advanced
    }

    public init(manager: MenuBarManager) {
        self.manager = manager
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab bar
                Picker("", selection: $selectedTab) {
                    Text("Presets").tag(CustomizerTab.presets)
                    Text("Sections").tag(CustomizerTab.sections)
                    Text("Style").tag(CustomizerTab.appearance)
                    Text("Advanced").tag(CustomizerTab.advanced)
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                // Tab content
                ScrollView {
                    switch selectedTab {
                    case .presets:    presetsTab
                    case .sections:   sectionsTab
                    case .appearance: appearanceTab
                    case .advanced:   advancedTab
                    }
                }
            }
            .navigationTitle("Customize Menu Bar")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        manager.saveToDisk()
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 480, height: 560)
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Presets tab
    // ═══════════════════════════════════════════════════════════════

    private var presetsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(MenuBarPreset.allCases) { preset in
                PresetCard(
                    preset: preset,
                    isActive: manager.activePreset == preset,
                    onSelect: { manager.applyPreset(preset) }
                )
            }
        }
        .padding()
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Sections tab (drag-to-reorder + toggles)
    // ═══════════════════════════════════════════════════════════════

    private var sectionsTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Drag to reorder. Toggle to show/hide.")
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal)

            List {
                ForEach(Array(manager.config.sections.enumerated()), id: \.element.id) { idx, section in
                    HStack {
                        Image(systemName: section.customIcon ?? section.section.defaultIcon)
                            .font(.system(size: 12))
                            .foregroundStyle(section.enabled ? theme.accent : theme.textSecondary)
                            .frame(width: 20)

                        Text(section.customTitle ?? section.section.displayName)
                            .font(.system(size: 13, weight: section.enabled ? .medium : .regular))
                            .foregroundStyle(section.enabled ? theme.textPrimary : theme.textSecondary)

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { manager.config.sections[idx].enabled },
                            set: { manager.config.sections[idx].enabled = $0 }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    }
                    .padding(.vertical, 2)
                }
                .onMove { source, destination in
                    manager.moveSection(from: source, to: destination)
                }
            }
            #if os(macOS)
            .listStyle(.inset(alternatesRowBackgrounds: true))
            #else
            .listStyle(.inset)
            #endif
        }
        .padding(.top)
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Appearance tab
    // ═══════════════════════════════════════════════════════════════

    private var appearanceTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Icon mode
            GroupBox("Menu Bar Icon") {
                Picker("Style", selection: $manager.config.iconMode) {
                    ForEach(MenuBarIconMode.allCases, id: \.self) { mode in
                        Text(iconModeLabel(mode)).tag(mode)
                    }
                }
                #if os(macOS)
                .pickerStyle(.radioGroup)
                #else
                .pickerStyle(.segmented)
                #endif

                if manager.config.iconMode == .custom {
                    TextField("SF Symbol name", text: Binding(
                        get: { manager.config.customIconName ?? "" },
                        set: { manager.config.customIconName = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }

            // Card style
            GroupBox("Card Style") {
                Picker("Style", selection: $manager.config.cardStyle) {
                    ForEach(MenuBarConfiguration.CardStyle.allCases, id: \.self) { style in
                        Text(style.rawValue.capitalized).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Compact mode
            GroupBox("Density") {
                Toggle("Compact mode", isOn: $manager.config.compactMode)
                Toggle("Show section headers", isOn: $manager.config.showSectionHeaders)
            }
        }
        .padding()
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Advanced tab
    // ═══════════════════════════════════════════════════════════════

    private var advancedTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox("Dimensions") {
                HStack {
                    Text("Width")
                    Slider(value: $manager.config.popoverWidth, in: 280...520, step: 10)
                    Text("\(Int(manager.config.popoverWidth))px")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 44, alignment: .trailing)
                }
                HStack {
                    Text("Max Height")
                    Slider(value: $manager.config.popoverMaxHeight, in: 300...900, step: 20)
                    Text("\(Int(manager.config.popoverMaxHeight))px")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 44, alignment: .trailing)
                }
            }

            GroupBox("Refresh") {
                Picker("Interval", selection: $manager.config.refreshInterval) {
                    Text("Manual").tag(TimeInterval(0))
                    Text("30s").tag(TimeInterval(30))
                    Text("1 min").tag(TimeInterval(60))
                    Text("2 min").tag(TimeInterval(120))
                    Text("5 min").tag(TimeInterval(300))
                }
                .pickerStyle(.segmented)
            }

            GroupBox("Config File") {
                HStack {
                    Text("~/.swoosh/menubar.json")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                    Spacer()
                    Button("Export") {
                        manager.saveToDisk()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding()
    }

    private func iconModeLabel(_ mode: MenuBarIconMode) -> String {
        switch mode {
        case .swooshLogo:    return "Swoosh Logo"
        case .providerMeter: return "Usage Meter (CodexBar-style)"
        case .statusDot:     return "Status Dot"
        case .providerIcon:  return "Active Provider Icon"
        case .custom:        return "Custom SF Symbol"
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Preset card
// ═══════════════════════════════════════════════════════════════════

struct PresetCard: View {
    let preset: MenuBarPreset
    let isActive: Bool
    let onSelect: () -> Void

    @Environment(\.swooshTheme) var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Preset icon
                Image(systemName: presetIcon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isActive ? theme.accent : theme.textSecondary)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.displayName)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(isActive ? theme.accent : theme.textPrimary)

                    Text(preset.description)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.accent)
                        .font(.system(size: 16))
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? theme.accent.opacity(0.08) : (isHovered ? theme.surface.opacity(0.4) : theme.surface.opacity(0.2)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isActive ? theme.accent.opacity(0.4) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var presetIcon: String {
        switch preset {
        case .swoosh:    return "sparkles"
        case .codexBar:  return "chart.bar.fill"
        case .minimal:   return "circle.fill"
        case .developer: return "hammer.fill"
        case .monitor:   return "gauge.with.dots.needle.33percent"
        case .agent:     return "person.fill"
        case .custom:    return "slider.horizontal.3"
        }
    }
}
