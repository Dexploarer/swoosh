// SwooshGenerativeUI/UISurfaceUpdate.swift — Surface envelope (0.4A)
//
// The top-level wire payload an agent emits to update a UI surface.
// Mirrors A2UI's `surfaceUpdate` shape: a stable surface ID, a root component
// to render, a flat list of components addressed by ID, plus monotonically
// increasing version + timestamp for replay/idempotency.

import Foundation

public struct UISurfaceUpdate: Codable, Sendable, Identifiable {
    /// Stable identifier for the surface being targeted (e.g. "chat-pane",
    /// "side-inspector", "approval-modal"). The host decides what each ID
    /// means and where to render it.
    public let surfaceID: String

    /// ID of the component that should be rendered at the top of the tree.
    /// Must exist in `components`.
    public let rootID: String

    /// Components in the surface, keyed implicitly by `id`. Order is not
    /// significant — children are referenced by string ID from their parent.
    public var components: [UIComponent]

    /// Monotonic counter — the host can use this to debounce duplicate
    /// applies and ensure ordered replay.
    public var version: Int

    /// When the surface was emitted (agent clock).
    public var timestamp: Date

    /// Optional title — useful when the surface is rendered as a sheet/window.
    public var title: String?

    /// Subtitle / context line.
    public var subtitle: String?

    /// Conformance to `Identifiable`. The surface ID is the natural key.
    public var id: String { surfaceID }

    public init(
        surfaceID: String,
        rootID: String,
        components: [UIComponent],
        version: Int = 1,
        timestamp: Date = Date(),
        title: String? = nil,
        subtitle: String? = nil
    ) {
        self.surfaceID = surfaceID
        self.rootID = rootID
        self.components = components
        self.version = version
        self.timestamp = timestamp
        self.title = title
        self.subtitle = subtitle
    }

    // MARK: - Lookups

    /// O(n) component lookup by ID. n is tiny in practice (tens at most), so
    /// keep it linear rather than maintaining a parallel dictionary.
    public func component(id: String) -> UIComponent? {
        components.first(where: { $0.id == id })
    }

    /// All component IDs reachable from `rootID` via child edges. Disconnected
    /// components in `components` are not visited — useful for warnings.
    public func reachableIDs() -> Set<String> {
        var seen = Set<String>()
        var stack = [rootID]
        while let id = stack.popLast() {
            guard !seen.contains(id), let c = component(id: id) else { continue }
            seen.insert(id)
            stack.append(contentsOf: c.body.childIDs)
        }
        return seen
    }

    /// Components present in the update but not referenced from the root.
    public func orphanIDs() -> [String] {
        let reachable = reachableIDs()
        return components.map(\.id).filter { !reachable.contains($0) }
    }

    // MARK: - JSON helpers

    public func encodeJSON() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(self)
    }

    public static func decodeJSON(_ data: Data) throws -> UISurfaceUpdate {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(UISurfaceUpdate.self, from: data)
    }
}

// MARK: - Validation

public extension UISurfaceUpdate {

    /// A validation problem found by `validate(against:)`.
    enum ValidationIssue: Equatable, Sendable {
        case rootMissing(String)
        case duplicateID(String)
        case childMissing(parent: String, missing: String)
        case typeNotInCatalog(componentID: String, typeName: String)
    }

    /// Walk the surface and report issues — missing root, duplicate IDs,
    /// dangling child references, types not allowed by the catalog.
    func validate(against catalog: ComponentCatalog) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        // Root must exist
        if component(id: rootID) == nil {
            issues.append(.rootMissing(rootID))
        }

        // Duplicate IDs
        var ids = Set<String>()
        for c in components {
            if ids.contains(c.id) {
                issues.append(.duplicateID(c.id))
            } else {
                ids.insert(c.id)
            }
        }

        // Dangling children + catalog gate
        for c in components {
            if !catalog.allows(c.body.typeName) {
                issues.append(.typeNotInCatalog(componentID: c.id, typeName: c.body.typeName))
            }
            for child in c.body.childIDs where !ids.contains(child) {
                issues.append(.childMissing(parent: c.id, missing: child))
            }
        }

        return issues
    }
}
