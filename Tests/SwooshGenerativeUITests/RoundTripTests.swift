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
        guard let recovered = SwooshGenerativeUISentinel.decode(envelope) else {
            return XCTFail("Failed to recover surface from envelope")
        }
        XCTAssertEqual(recovered.surfaceID, surface.surfaceID)
        XCTAssertEqual(recovered.rootID, surface.rootID)
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

    func testDisablingToolCallsBlocksAction() {
        let cat = ComponentCatalog.standard.disablingToolCalls()
        XCTAssertFalse(cat.allowsToolCalls)
        XCTAssertFalse(cat.allows(.toolCall(name: "x", arguments: [:])))
        XCTAssertTrue(cat.allows(.openURL("https://example.com")))
    }
}
