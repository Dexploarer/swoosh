// SwooshGenerativeUI/UIComponent.swift — Agent-emitted UI wire types (0.4A)
//
// Mirrors the shape of Google's A2UI `surfaceUpdate` payload (flat list of
// components addressed by ID), but is Codable-friendly in Swift and gated by
// `ComponentCatalog` for security. The agent can only request component
// *types* the client has registered — agents emit data, never code.
//
// Wire-format goals:
//   1. Stable JSON shape, version field, timestamp.
//   2. Recursive composition via *string ID references* (not nested structs)
//      so partial / streaming surface updates address children by name.
//   3. Every component carries `id` so updates can be diffed and re-applied.
//   4. Cleanly maps to A2UI v1.0 or MCP-UI if either becomes the standard.

import Foundation

// MARK: - Component

/// A single addressable component inside a `UISurfaceUpdate`. The `body`
/// determines what the renderer draws; `id` is how other components reference
/// it as a child.
public struct UIComponent: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let body: UIComponentBody
    public let style: UIStyle?

    public init(id: String, body: UIComponentBody, style: UIStyle? = nil) {
        self.id = id
        self.body = body
        self.style = style
    }
}

// MARK: - Body

/// The full set of built-in component bodies. Add a case here AND register a
/// renderer in `Builtins.swift` for it to be visible to agents.
///
/// Children are referenced by string ID — never nested directly. That keeps
/// the wire format flat, streaming-friendly, and trivially diff-able.
public enum UIComponentBody: Codable, Sendable, Hashable {
    // Text family
    case text(String)
    case heading(String, level: Int)
    case caption(String)
    case markdown(String)
    case code(String, language: String?)

    // Layout
    case column(children: [String], spacing: Double?, alignment: String?)
    case row(children: [String], spacing: Double?, alignment: String?)
    case grid(children: [String], columns: Int, spacing: Double?)
    case stack(children: [String])  // ZStack
    case spacer(minLength: Double?)
    case divider

    // Containers
    case card(child: String, title: String?, subtitle: String?)
    case glassPanel(child: String)
    case section(child: String, header: String?, footer: String?)
    case scrollContainer(child: String, axis: String?)

    // Indicators
    case statusChip(label: String, tint: String, systemImage: String?)
    case badge(label: String, count: Int?, tint: String?)
    case progress(value: Double, label: String?)
    case meter(value: Double, range: ClosedRangePair, label: String?)
    case loadingDots

    // Media
    case image(systemName: String?, url: String?, size: Double?)
    case avatar(systemName: String?, url: String?, label: String?)

    // Interaction
    case button(label: String, action: UIAction, systemImage: String?, style: String?)
    case link(label: String, url: String)
    case toggle(label: String, isOn: Bool, action: UIAction)

    // Data
    case list(items: [String], style: String?)
    case chart(series: [ChartSeries], kind: String, title: String?)
    case keyValue(pairs: [KeyValuePair])
    case table(columns: [String], rows: [[String]])

    /// Stringly-named discriminator used by the `ComponentCatalog` security
    /// gate. Always matches the case name — kept in sync via `Builtins.swift`.
    public var typeName: String {
        switch self {
        case .text:            return "text"
        case .heading:         return "heading"
        case .caption:         return "caption"
        case .markdown:        return "markdown"
        case .code:            return "code"
        case .column:          return "column"
        case .row:             return "row"
        case .grid:            return "grid"
        case .stack:           return "stack"
        case .spacer:          return "spacer"
        case .divider:         return "divider"
        case .card:            return "card"
        case .glassPanel:      return "glassPanel"
        case .section:         return "section"
        case .scrollContainer: return "scrollContainer"
        case .statusChip:      return "statusChip"
        case .badge:           return "badge"
        case .progress:        return "progress"
        case .meter:           return "meter"
        case .loadingDots:     return "loadingDots"
        case .image:           return "image"
        case .avatar:          return "avatar"
        case .button:          return "button"
        case .link:            return "link"
        case .toggle:          return "toggle"
        case .list:            return "list"
        case .chart:           return "chart"
        case .keyValue:        return "keyValue"
        case .table:           return "table"
        }
    }

    /// IDs of children referenced by this body (for graph traversal + diffing).
    public var childIDs: [String] {
        switch self {
        case let .column(children, _, _),
             let .row(children, _, _),
             let .grid(children, _, _),
             let .stack(children):
            return children
        case let .card(child, _, _),
             let .glassPanel(child),
             let .section(child, _, _),
             let .scrollContainer(child, _):
            return [child]
        case let .list(items, _):
            return items
        default:
            return []
        }
    }
}

// MARK: - Supporting wire types

/// A semantic action emitted when the user taps something. Kept open-ended
/// but typed — the host decides what each variant dispatches to.
public enum UIAction: Codable, Sendable, Hashable {
    case toolCall(name: String, arguments: [String: UIScalar])
    case openURL(String)
    case dispatchIntent(String, payload: [String: UIScalar])
    case setSurface(String, payload: [String: UIScalar])
    case approve(toolCallID: String, scope: String)
    case deny(toolCallID: String, reason: String)
    case noop
}

/// JSON-friendly scalar for action payloads. Codable as a JSON value.
public enum UIScalar: Codable, Sendable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self)   { self = .bool(v);   return }
        if let v = try? c.decode(Int.self)    { self = .int(v);    return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        throw DecodingError.dataCorruptedError(
            in: c,
            debugDescription: "UIScalar must be Bool / Int / Double / String / null"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:          try c.encodeNil()
        case .bool(let v):   try c.encode(v)
        case .int(let v):    try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        }
    }
}

public struct ChartSeries: Codable, Sendable, Hashable {
    public let name: String
    public let values: [Double]
    public let color: String?

    public init(name: String, values: [Double], color: String? = nil) {
        self.name = name
        self.values = values
        self.color = color
    }
}

public struct KeyValuePair: Codable, Sendable, Hashable {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// Codable shadow of `ClosedRange<Double>` (Swift's range isn't Codable
/// directly).
public struct ClosedRangePair: Codable, Sendable, Hashable {
    public let lower: Double
    public let upper: Double

    public init(_ lower: Double, _ upper: Double) {
        self.lower = lower
        self.upper = upper
    }
}

/// Optional styling hints attached to any component. The renderer reads these
/// through the active `SwooshTheme`; agents emit semantic tokens, not raw px.
public struct UIStyle: Codable, Sendable, Hashable {
    public var tint: String?            // "accent" | "success" | "warning" | "error" | "info" | hex
    public var background: String?      // semantic or hex
    public var foreground: String?
    public var padding: Double?
    public var cornerRadius: Double?
    public var fontSize: Double?
    public var fontWeight: String?      // "regular" | "medium" | "semibold" | "bold"
    public var fontDesign: String?      // "default" | "rounded" | "serif" | "monospaced"
    public var emphasize: Bool?

    public init(
        tint: String? = nil,
        background: String? = nil,
        foreground: String? = nil,
        padding: Double? = nil,
        cornerRadius: Double? = nil,
        fontSize: Double? = nil,
        fontWeight: String? = nil,
        fontDesign: String? = nil,
        emphasize: Bool? = nil
    ) {
        self.tint = tint
        self.background = background
        self.foreground = foreground
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.fontDesign = fontDesign
        self.emphasize = emphasize
    }
}
