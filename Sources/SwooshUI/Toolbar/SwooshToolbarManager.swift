// SwooshUI/Toolbar/SwooshToolbarManager.swift
// Observable manager for the window toolbar.

import SwiftUI
import Observation

@Observable
public final class SwooshToolbarManager: @unchecked Sendable {
    public var config: SwooshToolbarConfig
    public var badgeCounts: [SwooshToolbarItem: Int] = [:]

    public init() {
        self.config = SwooshToolbarConfig.load()
    }

    // MARK: - Mutation

    public func apply(preset: ToolbarPreset) {
        withAnimation(.spring(duration: 0.35)) {
            config = preset.config
        }
        trySave()
    }

    public func move(fromOffsets: IndexSet, toOffset: Int) {
        config.items.move(fromOffsets: fromOffsets, toOffset: toOffset)
        trySave()
    }

    public func remove(at offsets: IndexSet) {
        config.items.remove(atOffsets: offsets)
        trySave()
    }

    public func add(item: SwooshToolbarItem) {
        config.items.append(.init(item: item))
        trySave()
    }

    public func toggleVisible(id: String) {
        guard let idx = config.items.firstIndex(where: { $0.id == id }) else { return }
        config.items[idx].isVisible.toggle()
        trySave()
    }

    public func setLabelStyle(_ style: ToolbarItemConfig.ToolbarLabelStyle, for id: String) {
        guard let idx = config.items.firstIndex(where: { $0.id == id }) else { return }
        config.items[idx].labelStyle = style
        trySave()
    }

    public func setBadge(_ count: Int, for item: SwooshToolbarItem) {
        badgeCounts[item] = count > 0 ? count : nil
    }

    // MARK: - Persistence

    private func trySave() {
        try? config.save()
    }

    // MARK: - Available items not in toolbar

    public var availableItems: [SwooshToolbarItem] {
        let used = Set(config.items.map(\.item))
        return SwooshToolbarItem.allCases.filter { !used.contains($0) || $0.isLayoutElement }
    }
}
