// SwooshModels/CatalogActor.swift — Hardware-filtered catalog actor + CatalogEntry — 0.9T

import Foundation

// MARK: - Catalog entry

/// A single model in the catalog. This is the core data type.
public struct CatalogEntry: Codable, Sendable, Identifiable {
    public let id: String                      // Unique ID (e.g. "qwen3-14b")
    public let name: String                    // Human name (e.g. "Qwen3 14B")
    public let family: String                  // Model family (e.g. "Qwen3")
    public let version: String                 // Version string
    public let parameterCount: String          // e.g. "14B", "0.6B", "82M"
    public let sizeTier: ModelSizeTier
    public let estimatedMemoryGB: Double       // VRAM/unified memory at Q4
    public let capabilities: Set<ModelCapability>
    public let formats: Set<ModelFormat>
    public let sources: [ModelSource]
    public let defaultRoles: Set<ModelRole>    // What this model is good at
    public let license: String                 // e.g. "Apache 2.0", "MIT"

    // Install commands per source
    public let installCommands: [ModelSource: String]

    // Metadata
    public let description: String
    public let homepage: String?
    public let huggingFaceID: String?          // e.g. "Qwen/Qwen3-14B"
    public let ollamaTag: String?              // e.g. "qwen3:14b"
    public let isCurated: Bool                 // true = ships with Swoosh catalog

    public init(
        id: String, name: String, family: String, version: String,
        parameterCount: String, sizeTier: ModelSizeTier, estimatedMemoryGB: Double,
        capabilities: Set<ModelCapability>, formats: Set<ModelFormat>,
        sources: [ModelSource], defaultRoles: Set<ModelRole>, license: String,
        installCommands: [ModelSource: String], description: String,
        homepage: String? = nil, huggingFaceID: String? = nil, ollamaTag: String? = nil,
        isCurated: Bool = true
    ) {
        self.id = id; self.name = name; self.family = family; self.version = version
        self.parameterCount = parameterCount; self.sizeTier = sizeTier
        self.estimatedMemoryGB = estimatedMemoryGB; self.capabilities = capabilities
        self.formats = formats; self.sources = sources; self.defaultRoles = defaultRoles
        self.license = license; self.installCommands = installCommands
        self.description = description; self.homepage = homepage
        self.huggingFaceID = huggingFaceID; self.ollamaTag = ollamaTag
        self.isCurated = isCurated
    }
}

// MARK: - Model catalog actor

/// The central registry of all available models.
/// Combines curated entries + live HF/Ollama discovery.
public actor ModelCatalog {
    private var entries: [String: CatalogEntry] = [:]
    private let hardware: HardwareProfile

    public init(hardware: HardwareProfile? = nil) {
        self.hardware = hardware ?? .detectCurrent()
        // Load curated catalog
        for entry in Self.curatedModels {
            entries[entry.id] = entry
        }
    }

    // MARK: - Query

    /// All models that fit this hardware
    public func compatible() -> [CatalogEntry] {
        entries.values
            .filter { $0.estimatedMemoryGB <= hardware.usableMemoryGB }
            .sorted { $0.name < $1.name }
    }

    /// Models for a specific role that fit this hardware
    public func forRole(_ role: ModelRole) -> [CatalogEntry] {
        compatible().filter { $0.defaultRoles.contains(role) }
    }

    /// Models with a specific capability
    public func withCapability(_ cap: ModelCapability) -> [CatalogEntry] {
        compatible().filter { $0.capabilities.contains(cap) }
    }

    /// Models in a specific size tier
    public func inTier(_ tier: ModelSizeTier) -> [CatalogEntry] {
        compatible().filter { $0.sizeTier == tier }
    }

    /// Models at or below a size tier
    public func atOrBelow(_ tier: ModelSizeTier) -> [CatalogEntry] {
        compatible().filter { $0.sizeTier <= tier }
    }

    /// Search by name
    public func search(_ query: String) -> [CatalogEntry] {
        let q = query.lowercased()
        return compatible().filter {
            $0.name.lowercased().contains(q) ||
            $0.family.lowercased().contains(q) ||
            $0.id.lowercased().contains(q)
        }
    }

    /// Get a specific entry
    public func get(_ id: String) -> CatalogEntry? {
        entries[id]
    }

    /// Add a discovered or custom entry
    public func register(_ entry: CatalogEntry) {
        entries[entry.id] = entry
    }

    /// Summary grouped by role
    public func summary() -> [(role: ModelRole, models: [CatalogEntry])] {
        ModelRole.allCases.compactMap { role in
            let models = forRole(role)
            return models.isEmpty ? nil : (role: role, models: models)
        }
    }
}
