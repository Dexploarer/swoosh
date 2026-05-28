// SwooshModels/ProviderConfig.swift — 0.1A Data-driven provider definitions
//
// Lets providers, routes, and the active selection be defined in
// ~/.swoosh/providers.json instead of compile-time tables, so adding an
// OpenAI-/Anthropic-compatible endpoint or switching the active provider
// is a config edit, not a recompile. This is *additive*: the file is
// merged over the built-in defaults, and an absent/empty file changes
// nothing. `kind` maps to an existing SwooshProviders.ProviderKind — the
// config defines new INSTANCES of existing kinds, not brand-new provider
// types (those still need Swift). Pure data + file I/O; no provider deps.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Config model
// ═══════════════════════════════════════════════════════════════════

/// One user-defined provider instance. `kind` is a ProviderKind raw value
/// (e.g. "openAI", "anthropic", "localOpenAICompatible"). `secretRef` is
/// the `namespace.key` grammar resolved through SwooshSecrets — never a
/// raw key.
public struct ProviderConfigEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: String
    public var displayName: String
    public var baseURL: String?
    public var secretRef: String?
    public var defaultModel: String?
    public var enabled: Bool
    public var priority: Int?
    /// Optional per-role model overrides keyed by `ModelRole` raw value.
    public var models: [String: String]?

    public init(
        id: String,
        kind: String,
        displayName: String,
        baseURL: String? = nil,
        secretRef: String? = nil,
        defaultModel: String? = nil,
        enabled: Bool = true,
        priority: Int? = nil,
        models: [String: String]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.baseURL = baseURL
        self.secretRef = secretRef
        self.defaultModel = defaultModel
        self.enabled = enabled
        self.priority = priority
        self.models = models
    }

    /// Minimal structural validity. Deeper checks (kind is a real
    /// ProviderKind, baseURL reachable) belong to the factory that
    /// constructs the concrete provider.
    public var isStructurallyValid: Bool {
        !id.trimmingCharacters(in: .whitespaces).isEmpty
            && !kind.trimmingCharacters(in: .whitespaces).isEmpty
            && !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// A route override: which provider serves a role, at what model/priority.
/// Merged over the built-in route table by (role, providerID).
public struct ProviderRouteOverride: Codable, Sendable, Equatable {
    public var role: String
    public var providerID: String
    public var model: String
    public var priority: Int

    public init(role: String, providerID: String, model: String, priority: Int) {
        self.role = role
        self.providerID = providerID
        self.model = model
        self.priority = priority
    }
}

/// Top-level provider configuration loaded from ~/.swoosh/providers.json.
public struct ProviderConfig: Codable, Sendable, Equatable {
    /// The provider the router should prefer for every text role. Live
    /// switching writes this; the daemon also applies it as a route
    /// override so the change takes effect without a restart.
    public var activeProviderID: String?
    public var providers: [ProviderConfigEntry]
    public var routeOverrides: [ProviderRouteOverride]
    /// Schema version for forward migration.
    public var version: Int

    public init(
        activeProviderID: String? = nil,
        providers: [ProviderConfigEntry] = [],
        routeOverrides: [ProviderRouteOverride] = [],
        version: Int = 1
    ) {
        self.activeProviderID = activeProviderID
        self.providers = providers
        self.routeOverrides = routeOverrides
        self.version = version
    }

    public static let empty = ProviderConfig()

    /// Only the entries that pass structural validation and are enabled.
    public var enabledValidProviders: [ProviderConfigEntry] {
        providers.filter { $0.isStructurallyValid && $0.enabled }
    }

    // Tolerate older files missing newer keys.
    private enum CodingKeys: String, CodingKey {
        case activeProviderID, providers, routeOverrides, version
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.activeProviderID = try c.decodeIfPresent(String.self, forKey: .activeProviderID)
        self.providers = (try? c.decode([ProviderConfigEntry].self, forKey: .providers)) ?? []
        self.routeOverrides = (try? c.decode([ProviderRouteOverride].self, forKey: .routeOverrides)) ?? []
        self.version = (try? c.decode(Int.self, forKey: .version)) ?? 1
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Store
// ═══════════════════════════════════════════════════════════════════

/// Loads/saves ~/.swoosh/providers.json. Absent or unreadable → `.empty`
/// (the daemon then runs purely on built-in defaults), so a bad/missing
/// file never takes the agent offline.
public struct ProviderConfigStore: Sendable {
    public let url: URL

    /// - Parameter directory: the ~/.swoosh state directory.
    public init(directory: URL) {
        self.url = directory.appendingPathComponent("providers.json", isDirectory: false)
    }

    public func load() -> ProviderConfig {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(ProviderConfig.self, from: data) else {
            return .empty
        }
        return config
    }

    public func save(_ config: ProviderConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }

    /// Set the active provider and persist. Returns the updated config so
    /// callers can apply route overrides on the live router.
    public func setActiveProvider(_ id: String?) throws -> ProviderConfig {
        var config = load()
        config.activeProviderID = id
        try save(config)
        return config
    }
}
