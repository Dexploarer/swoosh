// SwooshGenerativeUI/SampleTool.swift — Reference tool emitting a UI surface (0.4A)
//
// A self-contained, dependency-free sample showing the canonical pattern:
// the tool builds a `UISurfaceUpdate`, wraps it in the sentinel envelope,
// and returns the resulting JSON string as its output. The host detects
// the sentinel and routes the surface to a `GenerativeSurfaceHost`.
//
// This file is intentionally NOT registered into the production registry —
// it's a reference + the basis for the GenerativeUI tests.

import Foundation

public enum SwooshGenerativeUISampleTool {

    /// Build a sample surface and return its sentinel-wrapped JSON envelope.
    /// The host treats the result like any other tool output but routes the
    /// envelope into the renderer instead of displaying raw JSON.
    public static func portfolioSnapshotEnvelope() throws -> Data {
        let surface = UISurfaceUpdate(
            surfaceID: "portfolio-snapshot",
            rootID: "root",
            components: [
                UIComponent(id: "root", body: .glassPanel(child: "col")),
                UIComponent(id: "col",  body: .column(
                    children: ["heading", "chips", "kvs", "chart", "actions"],
                    spacing: 14, alignment: "leading"
                )),
                UIComponent(id: "heading", body: .heading("Portfolio Snapshot", level: 1)),
                UIComponent(id: "chips", body: .row(
                    children: ["chipGain", "chipAlerts", "chipBalance"],
                    spacing: 8, alignment: "center"
                )),
                UIComponent(id: "chipGain", body: .statusChip(
                    label: "+4.2% / 24h", tint: "success", systemImage: "arrow.up.right"
                )),
                UIComponent(id: "chipAlerts", body: .statusChip(
                    label: "3 alerts", tint: "warning", systemImage: "bell"
                )),
                UIComponent(id: "chipBalance", body: .statusChip(
                    label: "$24,318", tint: "info", systemImage: "creditcard"
                )),
                UIComponent(id: "kvs", body: .keyValue(pairs: [
                    KeyValuePair(key: "SOL",  value: "121.45 (+2.1%)"),
                    KeyValuePair(key: "ETH",  value: "3,372.10 (+0.8%)"),
                    KeyValuePair(key: "BTC",  value: "62,840 (-0.4%)"),
                ])),
                UIComponent(id: "chart", body: .chart(
                    series: [
                        ChartSeries(name: "Portfolio", values: [22850, 23120, 23690, 23410, 23930, 24180, 24318]),
                    ],
                    kind: "area",
                    title: "Last 7 days"
                )),
                UIComponent(id: "actions", body: .row(
                    children: ["btnRefresh", "btnAlerts"],
                    spacing: 8, alignment: "center"
                )),
                UIComponent(id: "btnRefresh", body: .button(
                    label: "Refresh",
                    action: .toolCall(name: "swoosh.portfolio.refresh", arguments: [:]),
                    systemImage: "arrow.clockwise",
                    style: "glass"
                )),
                UIComponent(id: "btnAlerts", body: .button(
                    label: "Configure Alerts",
                    action: .setSurface("portfolio-alerts", payload: [:]),
                    systemImage: "bell.badge",
                    style: "glass"
                )),
            ],
            title: "Portfolio",
            subtitle: "Updated just now"
        )

        return try SwooshGenerativeUISentinel.envelope(for: surface)
    }

    /// Build an approval-prompt surface that asks the user to OK a specific
    /// tool call. Demonstrates the `.approve` / `.deny` action variants.
    public static func approvalPromptEnvelope(toolCallID: String, summary: String) throws -> Data {
        let surface = UISurfaceUpdate(
            surfaceID: "approval-\(toolCallID)",
            rootID: "root",
            components: [
                UIComponent(id: "root", body: .card(child: "col", title: "Approval needed", subtitle: nil)),
                UIComponent(id: "col",  body: .column(
                    children: ["summary", "buttons"],
                    spacing: 12, alignment: "leading"
                )),
                UIComponent(id: "summary", body: .markdown(summary)),
                UIComponent(id: "buttons", body: .row(
                    children: ["btnDeny", "btnApprove"],
                    spacing: 8, alignment: "center"
                )),
                UIComponent(id: "btnDeny", body: .button(
                    label: "Deny",
                    action: .deny(toolCallID: toolCallID, reason: "User declined"),
                    systemImage: "xmark.circle",
                    style: "bordered"
                )),
                UIComponent(id: "btnApprove", body: .button(
                    label: "Approve once",
                    action: .approve(toolCallID: toolCallID, scope: "once"),
                    systemImage: "checkmark.circle.fill",
                    style: "borderedProminent"
                )),
            ]
        )
        return try SwooshGenerativeUISentinel.envelope(for: surface)
    }
}
