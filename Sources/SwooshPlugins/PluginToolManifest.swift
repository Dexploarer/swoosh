// SwooshPlugins/PluginToolManifest.swift — Per-tool manifest with elizaOS-aligned metadata — 0.9A
//
// One `PluginToolManifest` per tool the plugin publishes. Carries the
// typed `SwooshPermission` (not a string — enforced at the schema level)
// plus the elizaOS-compatible `similes` / `examples` / `tags` fields so
// the planner can surface tools by intent, not just canonical name.
//
// Validation invariant (enforced in `PluginManifest.validate`): every
// tool's `permission` must appear in the parent manifest's
// `requestedPermissions` set. The host re-checks at enable time.

import Foundation
import SwooshTools

public struct PluginToolManifest: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    /// Permission the tool's bridge calls require via the firewall.
    /// Must appear in the parent plugin's `requestedPermissions` list — that
    /// invariant is checked by `PluginManifest.validate()` at install time.
    public let permission: SwooshPermission
    public let risk: ToolRisk
    public let requiresApproval: Bool
    /// elizaOS-style alias names that match the same intent. The planner
    /// can surface these alongside the canonical `name` to widen tool
    /// selection. Optional — left empty by tools that only have one name.
    public let similes: [String]
    /// Free-form example usages, shown to the model so it learns when to
    /// pick this tool. elizaOS uses paired `{user, agent}` messages; we
    /// accept the simpler "one line per example" form here and let
    /// authors paste the eliza shape verbatim if they prefer.
    public let examples: [String]
    /// Categorisation tags. Used for filtering, routing hints, and the
    /// planner's compressed catalog view.
    public let tags: [String]

    public init(
        id: String = UUID().uuidString, name: String, description: String,
        permission: SwooshPermission = .toolRead,
        risk: ToolRisk = .medium, requiresApproval: Bool = true,
        similes: [String] = [], examples: [String] = [], tags: [String] = []
    ) {
        self.id = id; self.name = name; self.description = description
        self.permission = permission
        self.risk = risk; self.requiresApproval = requiresApproval
        self.similes = similes; self.examples = examples; self.tags = tags
    }

    public var swooshToolName: String { "plugin.\(name)" }

    // Backward-compat decoding: manifests written before the typed
    // `permission` field existed should still load, defaulting to `.toolRead`
    // (the safest read-only permission). Validation will then reject the
    // plugin if `.toolRead` isn't in `requestedPermissions`.
    private enum CodingKeys: String, CodingKey {
        case id, name, description, permission, risk, requiresApproval
        case similes, examples, tags
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = c.decodeOrDefault(String.self, forKey: .id, default: UUID().uuidString)
        self.name = try c.decode(String.self, forKey: .name)
        self.description = try c.decode(String.self, forKey: .description)
        self.permission = c.decodeOrDefault(
            SwooshPermission.self, forKey: .permission, default: .toolRead
        )
        self.risk = c.decodeOrDefault(ToolRisk.self, forKey: .risk, default: .medium)
        self.requiresApproval = c.decodeOrDefault(
            Bool.self, forKey: .requiresApproval, default: true
        )
        self.similes = c.decodeOrDefault([String].self, forKey: .similes, default: [])
        self.examples = c.decodeOrDefault([String].self, forKey: .examples, default: [])
        self.tags = c.decodeOrDefault([String].self, forKey: .tags, default: [])
    }
}
