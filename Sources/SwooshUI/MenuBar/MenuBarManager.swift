// SwooshUI/MenuBar/MenuBarManager.swift — Menu bar state + persistence
//
// Manages the active menu bar configuration, loads/saves from disk,
// handles live credential discovery, and provides the observable state
// for SwiftUI views.

import SwiftUI
import Foundation
import SwooshSecrets

// ═══════════════════════════════════════════════════════════════════
// MARK: - Provider status (live state)
// ═══════════════════════════════════════════════════════════════════

/// Real-time status of a single provider credential.
public struct ProviderCredentialStatus: Identifiable, Sendable {
    public let id: String
    public let provider: KnownProvider
    public let displayName: String
    public let source: CredentialSource
    public let credentialKind: DiscoveredCredential.CredentialKind
    public let isHealthy: Bool
    public let lastChecked: Date?
    public let statusMessage: String?

    public init(provider: KnownProvider, source: CredentialSource,
                kind: DiscoveredCredential.CredentialKind,
                isHealthy: Bool = true, lastChecked: Date? = nil,
                statusMessage: String? = nil) {
        self.id = provider.rawValue
        self.provider = provider
        self.displayName = provider.displayName
        self.source = source
        self.credentialKind = kind
        self.isHealthy = isHealthy
        self.lastChecked = lastChecked
        self.statusMessage = statusMessage
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Menu bar manager
// ═══════════════════════════════════════════════════════════════════

@Observable
public final class MenuBarManager {
    /// Current layout configuration
    public var config: MenuBarConfiguration

    /// Active preset (nil if fully custom)
    public var activePreset: MenuBarPreset?

    /// Discovered provider credentials (live)
    public var providerStatuses: [ProviderCredentialStatus] = []

    /// Accessible browsers for cookie extraction
    public var accessibleBrowsers: [String] = []

    /// Last discovery time
    public var lastDiscoveryTime: Date?

    /// Is currently refreshing
    public var isRefreshing: Bool = false

    private static let configFileName = "menubar.json"

    public init(preset: MenuBarPreset = .swoosh) {
        self.activePreset = preset
        self.config = preset.configuration
    }

    // ── Persistence ──

    private static var configURL: URL {
        swooshHomeDirectoryForCurrentUser()
            .appendingPathComponent(".swoosh")
            .appendingPathComponent(configFileName)
    }

    /// Load configuration from disk, falling back to preset.
    public func loadFromDisk() {
        let url = Self.configURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let loaded = try JSONDecoder().decode(MenuBarConfiguration.self, from: data)
            self.config = loaded
            // Match to preset if possible
            self.activePreset = MenuBarPreset.allCases.first {
                $0.rawValue == loaded.presetName.lowercased()
            }
        } catch {
            print("[SwooshUI/MenuBar] Failed to load config: \(error)")
        }
    }

    /// Save current configuration to disk.
    public func saveToDisk() {
        let url = Self.configURL
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[SwooshUI/MenuBar] Failed to save config: \(error)")
        }
    }

    // ── Preset switching ──

    /// Switch to a preset, replacing the current configuration.
    public func applyPreset(_ preset: MenuBarPreset) {
        self.activePreset = preset
        self.config = preset.configuration
        saveToDisk()
    }

    // ── Section management ──

    /// Enabled sections in display order.
    public var enabledSections: [MenuBarSectionConfig] {
        config.sections.filter(\.enabled)
    }

    /// Toggle a section's enabled state.
    public func toggleSection(_ section: MenuBarSection) {
        if let idx = config.sections.firstIndex(where: { $0.section == section }) {
            config.sections[idx].enabled.toggle()
            activePreset = .custom
            saveToDisk()
        }
    }

    /// Move a section in the display order.
    public func moveSection(from source: IndexSet, to destination: Int) {
        config.sections.move(fromOffsets: source, toOffset: destination)
        activePreset = .custom
        saveToDisk()
    }

    // ── Credential discovery ──

    /// Run credential discovery and update provider statuses.
    @MainActor
    public func refreshCredentials() async {
        isRefreshing = true
        defer { isRefreshing = false }

        let discovered = CredentialScavenger.discoverAll()
        let browsers = KeychainScavenger.accessibleBrowsers()

        let statuses = discovered.map { cred in
            ProviderCredentialStatus(
                provider: cred.provider,
                source: cred.source,
                kind: cred.credentialKind,
                isHealthy: true,
                lastChecked: Date(),
                statusMessage: "Found via \(cred.source.rawValue)"
            )
        }

        // Update on main actor for SwiftUI
        self.providerStatuses = statuses
        self.accessibleBrowsers = browsers
        self.lastDiscoveryTime = Date()
    }
}
