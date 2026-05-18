// SwooshGenerativeUI/ComponentCatalog.swift — Renderable-type allowlist (0.4A)
//
// The catalog is the security boundary for agent-emitted UI: only types
// registered here will render. This is the same model A2UI uses — agents
// emit data, the catalog is the host's contract about which components
// exist client-side.
//
// Catalogs are immutable values (not actors). Composition is by union: a
// host that needs the standard catalog plus some custom components builds
// the union once at startup and passes it down.

import Foundation

public struct ComponentCatalog: Sendable, Equatable {
    /// Set of component `typeName`s that may render.
    public let allowedTypes: Set<String>

    public init(allowedTypes: Set<String>) {
        self.allowedTypes = allowedTypes
    }

    /// True when the catalog accepts `typeName`.
    public func allows(_ typeName: String) -> Bool {
        allowedTypes.contains(typeName)
    }

    /// Return a new catalog that accepts every type from either side. Useful
    /// for adding custom components on top of the standard catalog.
    public func union(_ other: ComponentCatalog) -> ComponentCatalog {
        ComponentCatalog(allowedTypes: allowedTypes.union(other.allowedTypes))
    }

    // MARK: - Built-in catalogs

    /// The standard catalog — every built-in body. Most hosts want this.
    public static let standard = ComponentCatalog(allowedTypes: [
        // Text
        "text", "heading", "caption", "markdown", "code",
        // Layout
        "column", "row", "grid", "stack", "spacer", "divider",
        // Containers
        "card", "glassPanel", "section", "scrollContainer",
        // Indicators
        "statusChip", "badge", "progress", "meter", "loadingDots",
        // Media
        "image", "avatar",
        // Interaction
        "button", "link", "toggle",
        // Data
        "list", "chart", "keyValue", "table",
    ])

    /// Minimal catalog — text + layout only. Use for unverified or low-trust
    /// agents where rich widgets shouldn't be exposed.
    public static let minimal = ComponentCatalog(allowedTypes: [
        "text", "heading", "caption", "markdown",
        "column", "row", "spacer", "divider",
        "card", "glassPanel",
    ])

    /// Read-only catalog — strips every interactive component. Use when the
    /// surface is being shown in a context where actions aren't safe yet
    /// (e.g. a preview before approval).
    public static let readOnly = ComponentCatalog(
        allowedTypes: ComponentCatalog.standard.allowedTypes
            .subtracting(["button", "link", "toggle"])
    )

    // MARK: - Action filtering

    /// Returns true if the catalog allows the supplied action variant.
    /// Most actions are universally OK, but `.toolCall` and
    /// `.dispatchIntent` must check that the catalog opts into them.
    public func allows(_ action: UIAction) -> Bool {
        switch action {
        case .openURL, .noop, .setSurface:
            return true
        case .approve, .deny:
            return allowedTypes.contains("button")
        case .toolCall:
            return allowsToolCalls
        case .dispatchIntent:
            return allowsIntents
        }
    }

    /// Catalogs include the `button` component implicitly imply that they
    /// allow tool-call actions; the host can override by composing a
    /// `.disablingToolCalls()` catalog on top.
    public var allowsToolCalls: Bool {
        allowedTypes.contains("button") && !allowedTypes.contains("__noToolCalls")
    }

    public var allowsIntents: Bool {
        allowedTypes.contains("button") && !allowedTypes.contains("__noIntents")
    }

    /// Return a copy with tool-calls explicitly disallowed via sentinel.
    public func disablingToolCalls() -> ComponentCatalog {
        ComponentCatalog(allowedTypes: allowedTypes.union(["__noToolCalls"]))
    }

    /// Return a copy with intents explicitly disallowed via sentinel.
    public func disablingIntents() -> ComponentCatalog {
        ComponentCatalog(allowedTypes: allowedTypes.union(["__noIntents"]))
    }
}
