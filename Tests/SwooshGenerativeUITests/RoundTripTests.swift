// SwooshGenerativeUITests/RoundTripTests.swift
//
// Codable round-trip + structural validation. These tests are the wire
// format's contract: a surface emitted by an agent must decode back into an
// identical structure on the host.

import XCTest
@testable import SwooshGenerativeUI

final class RoundTripTests: XCTestCase {

    func testSampleSurfaceRoundTrip() throws {
        let original = UISurfaceUpdate.sample()
        let data = try original.encodeJSON()
        let decoded = try UISurfaceUpdate.decodeJSON(data)

        XCTAssertEqual(decoded.surfaceID, original.surfaceID)
        XCTAssertEqual(decoded.rootID, original.rootID)
        XCTAssertEqual(decoded.components.count, original.components.count)

        for (a, b) in zip(decoded.components, original.components) {
            XCTAssertEqual(a.id, b.id)
            XCTAssertEqual(a.body, b.body)
        }
    }

    func testEnvelopeWrap() throws {
        let surface = UISurfaceUpdate.sample()
        let envelope = try SwooshGenerativeUISentinel.envelope(for: surface)
        guard let recovered = try SwooshGenerativeUISentinel.decode(envelope) else {
            return XCTFail("Failed to recover surface from envelope")
        }
        XCTAssertEqual(recovered.surfaceID, surface.surfaceID)
        XCTAssertEqual(recovered.rootID, surface.rootID)
    }

    func testEnvelopeDecodeReturnsNilWhenSentinelAbsent() throws {
        let data = Data(#"{"message":"plain tool output"}"#.utf8)
        XCTAssertNil(try SwooshGenerativeUISentinel.decode(data))
    }

    func testEnvelopeDecodeThrowsWhenSentinelMalformed() {
        let data = Data(#"{"_swoosh_ui":{"surfaceID":"broken"}}"#.utf8)
        XCTAssertThrowsError(try SwooshGenerativeUISentinel.decode(data))
    }

    func testValidationFlagsBrokenRoot() {
        let broken = UISurfaceUpdate.brokenSample()
        let issues = broken.validate(against: .standard)
        XCTAssertTrue(issues.contains { issue in
            if case .rootMissing("ghost") = issue { return true }
            return false
        })
    }

    func testValidationFlagsDanglingChild() {
        let surface = UISurfaceUpdate(
            surfaceID: "x",
            rootID: "root",
            components: [
                UIComponent(id: "root", body: .column(children: ["a", "missing"], spacing: nil, alignment: nil)),
                UIComponent(id: "a",    body: .text("hi")),
            ]
        )
        let issues = surface.validate(against: .standard)
        XCTAssertTrue(issues.contains { issue in
            if case let .childMissing(_, missing) = issue, missing == "missing" { return true }
            return false
        })
    }

    func testValidationFlagsDuplicateID() {
        let surface = UISurfaceUpdate(
            surfaceID: "x",
            rootID: "a",
            components: [
                UIComponent(id: "a", body: .text("first")),
                UIComponent(id: "a", body: .text("second")),
            ]
        )
        let issues = surface.validate(against: .standard)
        XCTAssertTrue(issues.contains { issue in
            if case .duplicateID("a") = issue { return true }
            return false
        })
    }

    func testCatalogBlocksUnauthorizedType() {
        let surface = UISurfaceUpdate(
            surfaceID: "x",
            rootID: "b",
            components: [
                UIComponent(id: "b", body: .button(
                    label: "Click", action: .noop, systemImage: nil, style: nil))
            ]
        )
        let issues = surface.validate(against: .readOnly)
        XCTAssertTrue(issues.contains { issue in
            if case .typeNotInCatalog(_, "button") = issue { return true }
            return false
        })
    }

    func testReachableIDsFindsTransitiveChildren() {
        let surface = UISurfaceUpdate(
            surfaceID: "x",
            rootID: "root",
            components: [
                UIComponent(id: "root", body: .column(children: ["a", "b"], spacing: nil, alignment: nil)),
                UIComponent(id: "a",    body: .row(children: ["a1"], spacing: nil, alignment: nil)),
                UIComponent(id: "a1",   body: .text("deep")),
                UIComponent(id: "b",    body: .text("flat")),
                UIComponent(id: "orphan", body: .text("alone")),
            ]
        )
        let reachable = surface.reachableIDs()
        XCTAssertEqual(reachable, ["root", "a", "a1", "b"])
        XCTAssertEqual(surface.orphanIDs(), ["orphan"])
    }

    func testActionsCodable() throws {
        let actions: [UIAction] = [
            .toolCall(name: "swoosh.test", arguments: ["x": .int(1), "y": .string("hi")]),
            .openURL("https://example.com"),
            .dispatchIntent("Greet", payload: ["name": .string("Sam")]),
            .setSurface("next", payload: [:]),
            .approve(toolCallID: "tc-1", scope: "once"),
            .deny(toolCallID: "tc-2", reason: "denied"),
            .noop,
        ]
        let data = try JSONEncoder().encode(actions)
        let back = try JSONDecoder().decode([UIAction].self, from: data)
        XCTAssertEqual(back, actions)
    }

    func testCatalogUnion() {
        let custom = ComponentCatalog(allowedTypes: ["customWidget"])
        let combined = ComponentCatalog.standard.union(custom)
        XCTAssertTrue(combined.allows("customWidget"))
        XCTAssertTrue(combined.allows("button"))
    }

    func testStandardCatalogMatchesBuiltInTypes() {
        XCTAssertEqual(ComponentCatalog.standard.allowedTypes, UIComponentBody.builtInTypeNames)
    }

    func testRepresentativeBodiesMatchBuiltInTypes() {
        let bodies: [UIComponentBody] = [
            .text(""),
            .heading("", level: 1),
            .caption(""),
            .markdown(""),
            .code("", language: nil),
            .column(children: [], spacing: nil, alignment: nil),
            .row(children: [], spacing: nil, alignment: nil),
            .grid(children: [], columns: 1, spacing: nil),
            .stack(children: []),
            .spacer(minLength: nil),
            .divider,
            .card(child: "", title: nil, subtitle: nil),
            .glassPanel(child: ""),
            .section(child: "", header: nil, footer: nil),
            .scrollContainer(child: "", axis: nil),
            .statusChip(label: "", tint: "accent", systemImage: nil),
            .badge(label: "", count: nil, tint: nil),
            .progress(value: 0, label: nil),
            .meter(value: 0, range: ClosedRangePair(0, 1), label: nil),
            .loadingDots,
            .image(systemName: nil, url: nil, size: nil),
            .avatar(systemName: nil, url: nil, label: nil),
            .button(label: "", action: .noop, systemImage: nil, style: nil),
            .link(label: "", url: "https://example.com"),
            .toggle(label: "", isOn: false, action: .noop),
            .list(items: [], style: nil),
            .chart(series: [], kind: "line", title: nil),
            .keyValue(pairs: []),
            .table(columns: [], rows: []),
        ]
        XCTAssertEqual(Set(bodies.map(\.typeName)), UIComponentBody.builtInTypeNames)
    }

    func testDisablingToolCallsBlocksAction() {
        let cat = ComponentCatalog.standard.disablingToolCalls()
        XCTAssertFalse(cat.allowsToolCalls)
        XCTAssertFalse(cat.allows(.toolCall(name: "x", arguments: [:])))
        XCTAssertTrue(cat.allows(.openURL("https://example.com")))
    }

    func testToolCallPolicyCanBlockToggleActionsEvenWhenToggleRenders() {
        let cat = ComponentCatalog.standard.disablingToolCalls()
        XCTAssertTrue(cat.allows("toggle"))
        XCTAssertFalse(cat.allows(.toolCall(name: "x", arguments: [:])))
    }

    func testHexParserRejectsMalformedHex() {
        XCTAssertNil(parseHexColor("#zzzzzz"))
        XCTAssertNil(parseHexColor("#12"))
        XCTAssertNil(parseHexColor("#abg"))
        XCTAssertNil(parseHexColor("##abc"))
        XCTAssertNil(parseHexColor("abc#"))
        XCTAssertEqual(parseHexColor("#abc"), RGBColor(
            red: 170.0 / 255.0,
            green: 187.0 / 255.0,
            blue: 204.0 / 255.0
        ))
    }

    func testTableRowsNormalizeToColumnCount() {
        XCTAssertEqual(normalizedTableRow(["a"], columnCount: 3), ["a", "", ""])
        XCTAssertEqual(normalizedTableRow(["a", "b", "c"], columnCount: 2), ["a", "b"])
        XCTAssertEqual(normalizedTableRow(["a", "b"], columnCount: 2), ["a", "b"])
    }

    func testChartPointIDsIncludeSeriesIndex() {
        let first = chartPoints(seriesID: "a", values: [1, 2]).map(\.id)
        let second = chartPoints(seriesID: "b", values: [1, 2]).map(\.id)
        XCTAssertEqual(first, ["a-0", "a-1"])
        XCTAssertEqual(second, ["b-0", "b-1"])
        XCTAssertTrue(Set(first).isDisjoint(with: second))
    }

    func testChartSeriesIDsUseStableContentKeysWithOccurrences() {
        let series = [
            ChartSeries(name: "A", values: [1, 2], color: nil),
            ChartSeries(name: "A", values: [1, 2], color: nil),
        ]
        XCTAssertEqual(chartSeriesItems(series).map(\.id), ["A||1.0,2.0#0", "A||1.0,2.0#1"])
    }

    func testListItemsUseComponentIDAndOccurrence() {
        let rendered = listItems(["a", "b", "a"])
        XCTAssertEqual(rendered.map(\.id), [
            UIListItemID(componentID: "a", occurrence: 0),
            UIListItemID(componentID: "b", occurrence: 0),
            UIListItemID(componentID: "a", occurrence: 1),
        ])
        XCTAssertEqual(rendered.map(\.number), [1, 2, 3])
    }

    func testTableCellIDsIncludeRowAndColumn() {
        XCTAssertEqual(
            tableCellIDs(row: 2, columnCount: 3),
            [
                UITableCellID(row: 2, column: 0),
                UITableCellID(row: 2, column: 1),
                UITableCellID(row: 2, column: 2),
            ]
        )
    }

    func testMeterBoundsClampAndNormalizeRange() {
        XCTAssertEqual(meterBounds(value: 2, range: ClosedRangePair(0, 1)), UIMeterBounds(lower: 0, upper: 1, value: 1))
        XCTAssertEqual(meterBounds(value: 3, range: ClosedRangePair(10, 2)), UIMeterBounds(lower: 2, upper: 10, value: 3))
        XCTAssertEqual(meterBounds(value: .nan, range: ClosedRangePair(0, 1)), UIMeterBounds(lower: 0, upper: 1, value: 0))
        XCTAssertEqual(meterBounds(value: 3, range: ClosedRangePair(1, 1)), UIMeterBounds(lower: 0, upper: 1, value: 1))
    }
}
