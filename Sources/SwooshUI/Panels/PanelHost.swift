// SwooshUI/Panels/PanelHost.swift — 0.9R Layout host with edit + DnD
//
// Responsive grid layout. Reads viewport width via GeometryReader and
// computes column count by breakpoints:
//   • ≤700pt   → 1 column   (tray, narrow window)
//   • 700-1100 → 2 columns
//   • 1100-1500→ 3 columns
//   • >1500pt  → 4 columns  (large display / fullscreen)
//
// The first `agentShell` panel — if present — pins at the top as a
// full-width hero strip so the chat surface always reads as the focal
// point. The rest flow into the adaptive grid below.
//
// Density (compact/cozy/comfy) scales the inner spacing + per-panel
// minimum height. The toolbar exposes a density picker in addition to
// the existing edit toggle.

import SwiftUI
import SwooshGenerativeUI

// ═══════════════════════════════════════════════════════════════════
// MARK: - Density
// ═══════════════════════════════════════════════════════════════════

public enum PanelDensity: String, Sendable, CaseIterable {
    case compact
    case cozy
    case comfy

    var spacing: CGFloat {
        switch self {
        case .compact: return 8
        case .cozy:    return 12
        case .comfy:   return 18
        }
    }

    var minPanelWidth: CGFloat {
        switch self {
        case .compact: return 280
        case .cozy:    return 320
        case .comfy:   return 360
        }
    }

    var heightMultiplier: CGFloat {
        switch self {
        case .compact: return 0.85
        case .cozy:    return 1.0
        case .comfy:   return 1.15
        }
    }

    var label: String {
        switch self {
        case .compact: return "Compact"
        case .cozy:    return "Cozy"
        case .comfy:   return "Comfortable"
        }
    }

    var icon: String {
        switch self {
        case .compact: return "rectangle.compress.vertical"
        case .cozy:    return "rectangle.split.2x1"
        case .comfy:   return "rectangle.expand.vertical"
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Host
// ═══════════════════════════════════════════════════════════════════

public struct PanelHost: View {

    // MARK: - Inputs

    @Bindable public var store: PanelLayoutStore
    public let surface: String
    public let context: PanelHostContext
    @Binding public var editing: Bool

    public init(
        store: PanelLayoutStore,
        surface: String,
        context: PanelHostContext,
        editing: Binding<Bool>
    ) {
        self.store = store
        self.surface = surface
        self.context = context
        self._editing = editing
    }

    // MARK: - State

    @State private var showingAddSheet = false
    @State private var density: PanelDensity = .cozy

    // MARK: - Body

    public var body: some View {
        let layout = store.layout(for: surface)
        let hero = layout.panels.first(where: { isHero($0) })
        let grid = layout.panels.filter { !isHero($0) }

        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: density.spacing + 4) {
                    if let hero {
                        heroStrip(hero, in: layout)
                    }
                    adaptiveGrid(grid, width: proxy.size.width, in: layout)
                    if editing {
                        addPanelButton
                    }
                }
                .padding(density.spacing + 4)
                .animation(.spring(duration: 0.25), value: density)
                .animation(.spring(duration: 0.25), value: columnCount(for: proxy.size.width))
            }
            .background(SwooshNeonTokens.Canvas.bg)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                densityMenu
            }
            ToolbarItem(placement: .primaryAction) {
                editButton
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddPanelSheet { kind in
                store.addPanel(kind, to: surface)
                showingAddSheet = false
            }
        }
    }

    // MARK: - Hero strip

    @ViewBuilder
    private func heroStrip(_ instance: PanelInstance, in layout: PanelLayout) -> some View {
        cardWithDnD(instance: instance, layout: layout)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 360 * density.heightMultiplier)
    }

    // MARK: - Adaptive grid

    @ViewBuilder
    private func adaptiveGrid(_ panels: [PanelInstance], width: CGFloat, in layout: PanelLayout) -> some View {
        let cols = columnCount(for: width)
        let columns = Array(repeating: GridItem(.flexible(), spacing: density.spacing + 4), count: cols)
        LazyVGrid(columns: columns, spacing: density.spacing + 4) {
            ForEach(panels) { instance in
                cardWithDnD(instance: instance, layout: layout)
                    .frame(minHeight: instance.kind.preferredHeight * density.heightMultiplier)
            }
        }
    }

    private func columnCount(for width: CGFloat) -> Int {
        switch width {
        case ..<700:   return 1
        case ..<1100:  return 2
        case ..<1500:  return 3
        default:       return 4
        }
    }

    private func isHero(_ instance: PanelInstance) -> Bool {
        if case .agentShell = instance.kind { return true }
        return false
    }

    // MARK: - Card + drag/drop

    @ViewBuilder
    private func cardWithDnD(instance: PanelInstance, layout: PanelLayout) -> some View {
        PanelCard(
            instance: instance,
            context: context,
            editing: editing,
            onRemove: { store.removePanel(id: instance.id, from: surface) }
        )
        .draggable(instance) {
            PanelDragPreview(instance: instance)
        }
        .dropDestination(for: PanelInstance.self) { dropped, _ in
            guard let source = dropped.first,
                  source.id != instance.id else { return false }
            reorder(source: source, target: instance, in: layout)
            return true
        } isTargeted: { _ in }
    }

    // MARK: - Toolbar

    private var editButton: some View {
        Button {
            withAnimation(.spring(duration: 0.2)) { editing.toggle() }
        } label: {
            Image(systemName: editing ? "checkmark.circle.fill" : "slider.horizontal.3")
                .foregroundStyle(SwooshNeonTokens.Accent.cyan)
        }
        .help(editing ? "Done editing" : "Customize layout")
    }

    private var densityMenu: some View {
        Menu {
            ForEach(PanelDensity.allCases, id: \.self) { d in
                Button {
                    density = d
                } label: {
                    Label(d.label, systemImage: d.icon)
                }
            }
        } label: {
            Image(systemName: density.icon)
                .foregroundStyle(SwooshNeonTokens.Canvas.text2)
        }
        .help("Layout density")
    }

    private var addPanelButton: some View {
        Button {
            showingAddSheet = true
        } label: {
            HStack(spacing: SwooshNeonTokens.Spacing.micro) {
                Image(systemName: "plus")
                Text("Add panel")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(SwooshNeonTokens.Accent.cyan)
            .frame(maxWidth: .infinity)
            .padding(.vertical, SwooshNeonTokens.Spacing.base + 2)
            .neonTile(.cyan, state: .focus, shape: .card)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reorder

    private func reorder(source: PanelInstance, target: PanelInstance, in layout: PanelLayout) {
        guard let from = layout.panels.firstIndex(where: { $0.id == source.id }),
              let to = layout.panels.firstIndex(where: { $0.id == target.id })
        else { return }
        var updated = layout
        let item = updated.panels.remove(at: from)
        updated.panels.insert(item, at: to)
        store.setLayout(updated)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Panel card (the capsule)
// ═══════════════════════════════════════════════════════════════════

struct PanelCard: View {
    let instance: PanelInstance
    let context: PanelHostContext
    let editing: Bool
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
                .background(SwooshNeonTokens.Line.rule)
                .padding(.horizontal, SwooshNeonTokens.Spacing.base + 4)
            content
                .padding(.horizontal, SwooshNeonTokens.Spacing.base + 4)
                .padding(.vertical, SwooshNeonTokens.Spacing.base + 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .neonTile(instance.kind.defaultAccent, state: editing ? .focus : .idle, shape: .card)
        .overlay(alignment: .topTrailing) {
            if editing {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(SwooshNeonTokens.Accent.gold)
                        .background(Circle().fill(SwooshNeonTokens.Canvas.bg))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.25), value: editing)
    }

    private var header: some View {
        HStack(spacing: SwooshNeonTokens.Spacing.base) {
            Image(systemName: instance.kind.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(instance.kind.defaultAccent.color)
            Text(instance.kind.title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            Spacer()
            if editing {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                    .help("Drag to reorder")
            }
        }
        .padding(.horizontal, SwooshNeonTokens.Spacing.base + 4)
        .padding(.vertical, SwooshNeonTokens.Spacing.base)
    }

    @ViewBuilder
    private var content: some View {
        PanelLibrary.view(for: instance, context: context)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Drag preview
// ═══════════════════════════════════════════════════════════════════

struct PanelDragPreview: View {
    let instance: PanelInstance
    var body: some View {
        HStack(spacing: SwooshNeonTokens.Spacing.micro) {
            Image(systemName: instance.kind.systemImage)
            Text(instance.kind.title)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(SwooshNeonTokens.Canvas.text1)
        .padding(.horizontal, SwooshNeonTokens.Spacing.base + 2)
        .padding(.vertical, SwooshNeonTokens.Spacing.micro + 2)
        .neonTile(instance.kind.defaultAccent, state: .focus, shape: .card)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Add panel sheet
// ═══════════════════════════════════════════════════════════════════

struct AddPanelSheet: View {
    let onPick: (PanelKind) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: SwooshNeonTokens.Spacing.base + 2) {
            HStack {
                Text("ADD PANEL")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(PanelKind.allBuiltIn, id: \.self) { kind in
                        Button {
                            onPick(kind)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: kind.systemImage)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(kind.defaultAccent.color)
                                    Spacer()
                                }
                                Text(kind.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                                Text(kind.blurb)
                                    .font(.system(size: 11))
                                    .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(3)
                            }
                            .padding(SwooshNeonTokens.Spacing.base + 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .neonTile(kind.defaultAccent, state: .idle, shape: .card)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(SwooshNeonTokens.Spacing.base * 2)
        .frame(minWidth: 540, minHeight: 560)
        .background(SwooshNeonTokens.Canvas.bg)
    }
}
