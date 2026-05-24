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

public struct PanelLayoutPreset: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let surface: String
    public let name: String
    public let description: String
    public let systemImage: String
    public let kinds: [PanelKind]

    public init(
        id: String,
        surface: String,
        name: String,
        description: String,
        systemImage: String,
        kinds: [PanelKind]
    ) {
        self.id = id
        self.surface = surface
        self.name = name
        self.description = description
        self.systemImage = systemImage
        self.kinds = kinds
    }

    public func makeLayout(surface: String? = nil) -> PanelLayout {
        PanelLayout(
            surface: surface ?? self.surface,
            panels: kinds.map { PanelInstance(kind: $0) }
        )
    }

    public static func defaultPreset(for surface: String) -> PanelLayoutPreset {
        switch surface {
        case "dashboard":
            return dashboardOperator
        case "ios":
            return iOSControl
        case "tray":
            return trayBriefing
        case "pill":
            return pillAgent
        default:
            return PanelLayoutPreset(
                id: "\(surface).agent",
                surface: surface,
                name: "Agent",
                description: "Single agent shell surface.",
                systemImage: "bubble.left.and.bubble.right",
                kinds: [.agentShell]
            )
        }
    }

    public static func options(for surface: String) -> [PanelLayoutPreset] {
        switch surface {
        case "dashboard":
            return [dashboardOperator, dashboardObserver, dashboardBuilder, dashboardMinimal]
        case "ios":
            return [iOSControl, iOSAgent, iOSValue]
        case "tray":
            return [trayBriefing]
        case "pill":
            return [pillAgent]
        default:
            return [defaultPreset(for: surface)]
        }
    }

    public static let dashboardOperator = PanelLayoutPreset(
        id: "dashboard.operator",
        surface: "dashboard",
        name: "Operator",
        description: "Agent shell, approvals, work, models, memory, and audit in one command center.",
        systemImage: "rectangle.3.group",
        kinds: [
            .agentShell,
            .approvals,
            .board,
            .goals,
            .workflows,
            .providerStatus,
            .localModels,
            .skills,
            .memories,
            .auditLog,
            .metrics,
            .agentOrb
        ]
    )

    public static let dashboardObserver = PanelLayoutPreset(
        id: "dashboard.observer",
        surface: "dashboard",
        name: "Observer",
        description: "Runtime, audit, usage, traces, providers, and firewall state for monitoring.",
        systemImage: "waveform.path.ecg.rectangle",
        kinds: [
            .agentShell,
            .providerStatus,
            .approvals,
            .auditLog,
            .usage,
            .costs,
            .observabilitySpans,
            .firewallSummary,
            .localModels,
            .mcpServers
        ]
    )

    public static let dashboardBuilder = PanelLayoutPreset(
        id: "dashboard.builder",
        surface: "dashboard",
        name: "Builder",
        description: "Skills, goals, workflows, tools, plugins, and custom generative surfaces.",
        systemImage: "hammer",
        kinds: [
            .agentShell,
            .skills,
            .goals,
            .manifests,
            .workflows,
            .triggers,
            .toolCatalog,
            .plugins,
            .mcpServers,
            .mediaGallery,
            .themePalette
        ]
    )

    public static let dashboardMinimal = PanelLayoutPreset(
        id: "dashboard.minimal",
        surface: "dashboard",
        name: "Minimal",
        description: "Quiet agent surface with only approvals, providers, and audit nearby.",
        systemImage: "rectangle.compress.vertical",
        kinds: [
            .agentShell,
            .approvals,
            .providerStatus,
            .auditLog
        ]
    )

    public static let iOSControl = PanelLayoutPreset(
        id: "ios.control",
        surface: "ios",
        name: "Control",
        description: "Compact controls that sit beside the chat-first iPhone shell.",
        systemImage: "square.grid.2x2",
        kinds: [
            .recentChats,
            .providerStatus,
            .approvals,
            .goals,
            .localModels,
            .skills,
            .voiceTranscript,
            .wallet
        ]
    )

    public static let iOSAgent = PanelLayoutPreset(
        id: "ios.agent",
        surface: "ios",
        name: "Agent",
        description: "Recent chats, voice, skills, memory, and active goals.",
        systemImage: "bubble.left.and.bubble.right",
        kinds: [
            .recentChats,
            .voiceTranscript,
            .skills,
            .memories,
            .goals,
            .approvals
        ]
    )

    public static let iOSValue = PanelLayoutPreset(
        id: "ios.value",
        surface: "ios",
        name: "Value",
        description: "Wallet, trading, providers, and approvals for mobile control.",
        systemImage: "creditcard",
        kinds: [
            .wallet,
            .walletAnalytics,
            .walletAssets,
            .providerStatus,
            .approvals,
            .tradingCapabilities
        ]
    )

    public static let trayBriefing = PanelLayoutPreset(
        id: "tray.briefing",
        surface: "tray",
        name: "Briefing",
        description: "Agent shell, recent chats, and provider state for the menu bar.",
        systemImage: "menubar.rectangle",
        kinds: [
            .agentShell,
            .recentChats,
            .providerStatus
        ]
    )

    public static let pillAgent = PanelLayoutPreset(
        id: "pill.agent",
        surface: "pill",
        name: "Agent",
        description: "Single compact agent shell for the voice pill.",
        systemImage: "capsule",
        kinds: [
            .agentShell
        ]
    )
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

    public func applyPreset(_ preset: PanelLayoutPreset, to surface: String? = nil) {
        setLayout(preset.makeLayout(surface: surface ?? preset.surface))
    }

    // ── Defaults ─────────────────────────────────────────────────────

    /// Stock layout for surfaces that have no saved customization yet.
    private func defaultLayout(for surface: String) -> PanelLayout {
        PanelLayoutPreset.defaultPreset(for: surface).makeLayout(surface: surface)
    }

    // ── Disk ─────────────────────────────────────────────────────────

    private func file(surface: String) -> URL {
        let safe = surface.replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent("\(safe).json")
    }

    private func loadFromDisk(surface: String) -> PanelLayout? {
        let url = file(surface: surface)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let layout = try? JSONDecoder().decode(PanelLayout.self, from: data) else { return nil }
        return layout.panels.isEmpty ? nil : layout
    }

    private func writeToDisk(_ layout: PanelLayout) {
        let url = file(surface: layout.surface)
        if let data = try? JSONEncoder().encode(layout) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
