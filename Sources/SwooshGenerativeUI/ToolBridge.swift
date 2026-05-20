// SwooshGenerativeUI/ToolBridge.swift — Tool result ↔ UISurfaceUpdate (0.4A)
//
// Tools in Swoosh return `output: JSONValue?`. To emit a UI surface, a tool
// embeds a `UISurfaceUpdate` under a stable sentinel key. The host detects
// the sentinel and routes the payload to the renderer instead of (or
// alongside) displaying raw JSON.

import Foundation

public enum SwooshGenerativeUISentinel {
    /// Key under which a tool's `output` carries a UI surface.
    public static let key = "_swoosh_ui"

    /// Sentinel envelope wrapping a `UISurfaceUpdate` as JSON inside a tool
    /// output. Encoded as `{ "_swoosh_ui": { ... surface ... } }`.
    public static func envelope(for surface: UISurfaceUpdate) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        struct Wrapper: Encodable {
            let _swoosh_ui: UISurfaceUpdate
            enum CodingKeys: String, CodingKey { case _swoosh_ui }
        }
        return try enc.encode(Wrapper(_swoosh_ui: surface))
    }

    /// Decode a surface from a tool-output blob carrying the sentinel.
    /// Returns nil when the blob isn't a surface envelope.
    public static func decode(_ data: Data) -> UISurfaceUpdate? {
        struct Wrapper: Decodable {
            let _swoosh_ui: UISurfaceUpdate
            enum CodingKeys: String, CodingKey { case _swoosh_ui }
        }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(Wrapper.self, from: data))?._swoosh_ui
    }

    /// Inspect a string output for a sentinel surface (UTF-8). Cheap path
    /// when the tool returns its JSON as a string instead of `JSONValue`.
    public static func decode(from string: String) -> UISurfaceUpdate? {
        guard let data = string.data(using: .utf8) else { return nil }
        return decode(data)
    }
}

// MARK: - Sample fixtures

public extension UISurfaceUpdate {
    /// A hand-built sample surface used by tests and previews. Composed of
    /// a glass panel containing a column: a heading, a status chip row, a
    /// chart, and an action button.
    static func sample() -> UISurfaceUpdate {
        UISurfaceUpdate(
            surfaceID: "sample",
            rootID: "root",
            components: [
                UIComponent(id: "root", body: .glassPanel(child: "col")),
                UIComponent(id: "col",  body: .column(
                    children: ["title", "chips", "chart", "actions"],
                    spacing: 12, alignment: "leading"
                )),
                UIComponent(id: "title", body: .heading("Portfolio Update", level: 1)),
                UIComponent(id: "chips", body: .row(
                    children: ["chip1", "chip2", "chip3"],
                    spacing: 6, alignment: "center"
                )),
                UIComponent(id: "chip1", body: .statusChip(label: "+4.2%", tint: "success", systemImage: "arrow.up.right")),
                UIComponent(id: "chip2", body: .statusChip(label: "3 alerts", tint: "warning", systemImage: "bell")),
                UIComponent(id: "chip3", body: .statusChip(label: "All healthy", tint: "info", systemImage: "heart")),
                UIComponent(id: "chart", body: .chart(
                    series: [
                        ChartSeries(name: "SOL", values: [142, 148, 151, 158, 162, 160, 167]),
                        ChartSeries(name: "ETH", values: [3200, 3250, 3280, 3260, 3310, 3340, 3370]),
                    ],
                    kind: "line",
                    title: "7-day trend"
                )),
                UIComponent(id: "actions", body: .row(
                    children: ["btn1", "btn2"],
                    spacing: 8, alignment: "center"
                )),
                UIComponent(id: "btn1", body: .button(
                    label: "Refresh",
                    action: .toolCall(name: "swoosh.portfolio.refresh", arguments: [:]),
                    systemImage: "arrow.clockwise",
                    style: "glass"
                )),
                UIComponent(id: "btn2", body: .button(
                    label: "View Detail",
                    action: .setSurface("portfolio-detail", payload: [:]),
                    systemImage: "arrow.up.right.square",
                    style: "glass"
                )),
            ],
            title: "Portfolio",
            subtitle: "Updated just now"
        )
    }

    /// Validation-failure fixture: references a missing root.
    static func brokenSample() -> UISurfaceUpdate {
        UISurfaceUpdate(
            surfaceID: "broken",
            rootID: "ghost",
            components: [
                UIComponent(id: "actual", body: .text("orphan"))
            ]
        )
    }
}
