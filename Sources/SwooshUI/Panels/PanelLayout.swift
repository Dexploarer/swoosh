// SwooshUI/Panels/PanelLayout.swift — 0.9R Layout model + store
//
// `PanelInstance` is one placed capsule (id + kind + per-instance config).
// `PanelLayout` is an ordered list of instances for a single surface.
// `PanelLayoutStore` persists layouts to disk and broadcasts mutations.
//
// File location:
//   ~/Library/Application Support/ai.swoosh.agent/panels/<surface>.json

import Foundation
import Observation
import CoreTransferable
import UniformTypeIdentifiers

// ═══════════════════════════════════════════════════════════════════
// MARK: - PanelInstance
// ═══════════════════════════════════════════════════════════════════

public struct PanelInstance: Codable, Sendable, Identifiable, Hashable, Transferable {
    public let id: UUID
    public var kind: PanelKind
    /// Free-form per-instance configuration (e.g. "wallet shows compact"
    /// or a chart's lookback window).
    public var config: [String: String]

    public init(
        id: UUID = UUID(),
        kind: PanelKind,
        config: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.config = config
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .swooshPanel)
    }
}

public extension UTType {
    /// MIME for cross-app drag-drop of a panel instance. Synthesized so
    /// SwiftUI's draggable/dropDestination can match it.
    static var swooshPanel: UTType {
        UTType(exportedAs: "ai.swoosh.panel", conformingTo: .data)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - PanelLayout
// ═══════════════════════════════════════════════════════════════════

public struct PanelLayout: Codable, Sendable, Equatable {
    /// Surface this layout belongs to ("tray", "dashboard", "pill", etc).
    public let surface: String
    public var panels: [PanelInstance]

    public init(surface: String, panels: [PanelInstance] = []) {
        self.surface = surface
        self.panels = panels
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Store
// ═══════════════════════════════════════════════════════════════════

@MainActor
@Observable
public final class PanelLayoutStore {

    public private(set) var layouts: [String: PanelLayout] = [:]

    private let directory: URL
    private let fm = FileManager.default

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = (try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directory = base.appendingPathComponent("ai.swoosh.agent/panels", isDirectory: true)
        }
        try? fm.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    // ── Layout access ────────────────────────────────────────────────

    /// Fetch (or build a default) layout for a surface.
    public func layout(for surface: String) -> PanelLayout {
        if let cached = layouts[surface] { return cached }
        if let disk = loadFromDisk(surface: surface) {
            layouts[surface] = disk
            return disk
        }
        let defaultLayout = defaultLayout(for: surface)
        layouts[surface] = defaultLayout
        return defaultLayout
    }

    /// Replace a surface's layout in memory and on disk.
    public func setLayout(_ layout: PanelLayout) {
        layouts[layout.surface] = layout
        writeToDisk(layout)
    }

    public func addPanel(_ kind: PanelKind, to surface: String) {
        var layout = self.layout(for: surface)
        layout.panels.append(PanelInstance(kind: kind))
        setLayout(layout)
    }

    public func removePanel(id: UUID, from surface: String) {
        var layout = self.layout(for: surface)
        layout.panels.removeAll { $0.id == id }
        setLayout(layout)
    }

    public func movePanel(from source: IndexSet, to dest: Int, surface: String) {
        var layout = self.layout(for: surface)
        layout.panels.move(fromOffsets: source, toOffset: dest)
        setLayout(layout)
    }

    public func reset(surface: String) {
        let fresh = defaultLayout(for: surface)
        setLayout(fresh)
    }

    // ── Defaults ─────────────────────────────────────────────────────

    /// Stock layout for surfaces that have no saved customization yet.
    private func defaultLayout(for surface: String) -> PanelLayout {
        switch surface {
        case "tray":
            return PanelLayout(surface: surface, panels: [
                .init(kind: .agentShell),
                .init(kind: .recentChats),
                .init(kind: .providerStatus),
            ])
        case "dashboard":
            return PanelLayout(surface: surface, panels: [
                .init(kind: .agentShell),
                .init(kind: .recentChats),
                .init(kind: .wallet),
                .init(kind: .walletAnalytics),
                .init(kind: .modelPicker),
                .init(kind: .skills),
                .init(kind: .providerStatus),
                .init(kind: .auditLog),
            ])
        case "pill":
            return PanelLayout(surface: surface, panels: [
                .init(kind: .agentShell),
            ])
        default:
            return PanelLayout(surface: surface, panels: [
                .init(kind: .agentShell),
            ])
        }
    }

    // ── Disk ─────────────────────────────────────────────────────────

    private func file(surface: String) -> URL {
        let safe = surface.replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent("\(safe).json")
    }

    private func loadFromDisk(surface: String) -> PanelLayout? {
        let url = file(surface: surface)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PanelLayout.self, from: data)
    }

    private func writeToDisk(_ layout: PanelLayout) {
        let url = file(surface: layout.surface)
        if let data = try? JSONEncoder().encode(layout) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
