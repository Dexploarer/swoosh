// SwooshUI/Toolbar/SwooshToolbarCustomizerView.swift
// Full toolbar customization UI — drag-to-reorder, preset picker,
// per-item visibility, label style, icon size, badge toggle.

import SwiftUI

public struct SwooshToolbarCustomizerView: View {
    @Bindable var manager: SwooshToolbarManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Tab = .presets
    @State private var dragging: String?

    enum Tab: Hashable { case presets, items, appearance }

    public init(manager: SwooshToolbarManager) { self.manager = manager }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                Picker("Tab", selection: $selectedTab) {
                    Text("Presets").tag(Tab.presets)
                    Text("Items").tag(Tab.items)
                    Text("Appearance").tag(Tab.appearance)
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                switch selectedTab {
                case .presets:    presetsTab
                case .items:      itemsTab
                case .appearance: appearanceTab
                }
            }
            .navigationTitle("Customize Toolbar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        try? manager.config.save()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 480)
    }

    // MARK: - Presets tab

    private var presetsTab: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 12) {
                ForEach(ToolbarPreset.all) { preset in
                    ToolbarPresetCard(preset: preset, isCurrent: isCurrentPreset(preset)) {
                        withAnimation { manager.apply(preset: preset) }
                    }
                }
            }
            .padding()
        }
    }

    private func isCurrentPreset(_ preset: ToolbarPreset) -> Bool {
        // Simple heuristic — same item count and same first items
        let presetItems = preset.config.items.map(\.item.rawValue)
        let currentItems = manager.config.items.map(\.item.rawValue)
        return presetItems == currentItems
    }

    // MARK: - Items tab

    private var itemsTab: some View {
        HStack(spacing: 0) {
            // Active items list (drag to reorder)
            VStack(alignment: .leading, spacing: 0) {
                Text("TOOLBAR ITEMS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                List {
                    ForEach(manager.config.items) { cfg in
                        ToolbarItemRow(cfg: cfg,
                            onToggle: { manager.toggleVisible(id: cfg.id) },
                            onStyleChange: { style in manager.setLabelStyle(style, for: cfg.id) },
                            onRemove: {
                                if let idx = manager.config.items.firstIndex(where: { $0.id == cfg.id }) {
                                    manager.remove(at: IndexSet(integer: idx))
                                }
                            }
                        )
                    }
                    .onMove { from, to in manager.move(fromOffsets: from, toOffset: to) }
                }
                .listStyle(.inset)
            }
            .frame(minWidth: 280)

            Divider()

            // Available items palette
            VStack(alignment: .leading, spacing: 0) {
                Text("AVAILABLE ITEMS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                List(manager.availableItems) { item in
                    HStack {
                        Image(systemName: item.icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(item.accentColor)
                            .frame(width: 24)
                        Text(item.displayName)
                            .font(.system(size: 13))
                        Spacer()
                        Button {
                            withAnimation { manager.add(item: item) }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            }
            .frame(minWidth: 200)
        }
    }

    // MARK: - Appearance tab

    private var appearanceTab: some View {
        Form {
            Section("Icon Size") {
                Slider(value: $manager.config.iconSize, in: 14...28, step: 2)

                HStack(spacing: 16) {
                    ForEach([14, 16, 18, 20, 22, 24, 28], id: \.self) { size in
                        Button {
                            withAnimation { manager.config.iconSize = CGFloat(size) }
                        } label: {
                            Image(systemName: "sparkles")
                                .font(.system(size: CGFloat(size) * 0.7))
                                .frame(width: 36, height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(manager.config.iconSize == CGFloat(size)
                                              ? Color.accentColor.opacity(0.2)
                                              : Color.secondary.opacity(0.1))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Global Label Style") {
                Picker("Label Style", selection: $manager.config.globalLabelStyle) {
                    Text("Icon Only").tag(ToolbarItemConfig.ToolbarLabelStyle.iconOnly)
                    Text("Label Only").tag(ToolbarItemConfig.ToolbarLabelStyle.labelOnly)
                    Text("Icon + Label").tag(ToolbarItemConfig.ToolbarLabelStyle.iconAndLabel)
                }
                .pickerStyle(.segmented)

                Button("Apply to all items") {
                    for idx in manager.config.items.indices {
                        manager.config.items[idx].labelStyle = manager.config.globalLabelStyle
                    }
                }
                .buttonStyle(.bordered)
            }

            Section("Badges") {
                Toggle("Show badge counts", isOn: $manager.config.showBadges)
            }

            Section("Reset") {
                Button("Restore Defaults") {
                    withAnimation { manager.config = .default }
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Supporting views

private struct ToolbarPresetCard: View {
    let preset: ToolbarPreset
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: preset.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isCurrent ? .white : .secondary)
                    Spacer()
                    if isCurrent {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white)
                    }
                }

                Text(preset.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isCurrent ? .white : .primary)

                Text(preset.description)
                    .font(.system(size: 11))
                    .foregroundStyle(isCurrent ? .white.opacity(0.85) : .secondary)
                    .lineLimit(2)

                // Mini item preview
                HStack(spacing: 4) {
                    ForEach(preset.config.items.prefix(6), id: \.id) { cfg in
                        if cfg.item.isLayoutElement {
                            Rectangle()
                                .fill(.white.opacity(0.3))
                                .frame(width: 1, height: 16)
                        } else {
                            Image(systemName: cfg.item.icon)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(isCurrent ? .white.opacity(0.9) : cfg.item.accentColor)
                        }
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isCurrent
                          ? AnyShapeStyle(LinearGradient(colors: [.accentColor, .accentColor.opacity(0.7)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(Color.secondary.opacity(0.08)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isCurrent ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ToolbarItemRow: View {
    let cfg: ToolbarItemConfig
    let onToggle: () -> Void
    let onStyleChange: (ToolbarItemConfig.ToolbarLabelStyle) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .font(.system(size: 12))

            Toggle("", isOn: .init(
                get: { cfg.isVisible },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .scaleEffect(0.7)

            Image(systemName: cfg.item.icon)
                .foregroundStyle(cfg.item.accentColor)
                .frame(width: 20)

            Text(cfg.effectiveLabel)
                .font(.system(size: 13))
                .opacity(cfg.isVisible ? 1 : 0.4)

            Spacer()

            if !cfg.item.isLayoutElement {
                Picker("", selection: .init(
                    get: { cfg.labelStyle },
                    set: { onStyleChange($0) }
                )) {
                    Image(systemName: "photo").tag(ToolbarItemConfig.ToolbarLabelStyle.iconOnly)
                    Image(systemName: "textformat").tag(ToolbarItemConfig.ToolbarLabelStyle.labelOnly)
                    Image(systemName: "photo.on.rectangle").tag(ToolbarItemConfig.ToolbarLabelStyle.iconAndLabel)
                }
                .pickerStyle(.segmented)
                .frame(width: 90)
            }

            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}
