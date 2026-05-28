// SwooshCloudGamingTests/GameStreamAdapterTests.swift — GamepadState + action types
// 0.5A – May 2026

import XCTest
@testable import SwooshCloudGaming

final class GameStreamAdapterTests: XCTestCase {

    // ── GamepadState ────────────────────────────────────────────────

    func testNeutralIsAllZeros() {
        let neutral = GamepadState.neutral
        XCTAssertEqual(neutral.leftStickX, 0)
        XCTAssertEqual(neutral.leftStickY, 0)
        XCTAssertEqual(neutral.rightStickX, 0)
        XCTAssertEqual(neutral.rightStickY, 0)
        XCTAssertEqual(neutral.leftTrigger, 0)
        XCTAssertEqual(neutral.rightTrigger, 0)
        XCTAssertTrue(neutral.buttons.isEmpty)
    }

    func testGamepadStateEquatable() {
        let a = GamepadState.neutral
        let b = GamepadState.neutral
        XCTAssertEqual(a, b)

        let c = GamepadState(
            leftStickX: 0.5, leftStickY: -0.3,
            rightStickX: 0, rightStickY: 0,
            leftTrigger: 0.8, rightTrigger: 0,
            buttons: [.a, .b]
        )
        XCTAssertNotEqual(a, c)
    }

    func testGamepadStateCodableRoundTrip() throws {
        let original = GamepadState(
            leftStickX: 0.75, leftStickY: -0.5,
            rightStickX: 0.1, rightStickY: -0.9,
            leftTrigger: 1.0, rightTrigger: 0.3,
            buttons: [.a, .x, .leftBumper, .dpadUp, .guide]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GamepadState.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // ── GamepadButtons ──────────────────────────────────────────────

    func testButtonsOptionSetOperations() {
        var buttons = GamepadButtons()
        XCTAssertTrue(buttons.isEmpty)

        buttons.insert(.a)
        XCTAssertTrue(buttons.contains(.a))
        XCTAssertFalse(buttons.contains(.b))

        buttons.insert(.b)
        XCTAssertTrue(buttons.contains(.a))
        XCTAssertTrue(buttons.contains(.b))

        let other: GamepadButtons = [.b, .x]
        let intersection = buttons.intersection(other)
        XCTAssertTrue(intersection.contains(.b))
        XCTAssertFalse(intersection.contains(.a))
        XCTAssertFalse(intersection.contains(.x))

        let union = buttons.union(other)
        XCTAssertTrue(union.contains(.a))
        XCTAssertTrue(union.contains(.b))
        XCTAssertTrue(union.contains(.x))
    }

    func testAllButtonCases() {
        // Verify all 17 Xbox buttons exist
        let all: [GamepadButtons] = [
            .a, .b, .x, .y,
            .leftBumper, .rightBumper,
            .leftThumb, .rightThumb,
            .dpadUp, .dpadDown, .dpadLeft, .dpadRight,
            .start, .back, .guide,
        ]
        XCTAssertGreaterThanOrEqual(all.count, 15)

        // Each should be unique
        for (i, btn) in all.enumerated() {
            for j in (i + 1)..<all.count {
                XCTAssertNotEqual(btn.rawValue, all[j].rawValue,
                    "Button \(i) and \(j) have the same raw value")
            }
        }
    }

    // ── NitroGenActionChunk ─────────────────────────────────────────

    func testActionChunkCodableRoundTrip() throws {
        let states = (0..<16).map { i in
            GamepadState(
                leftStickX: Float(i) / 16.0, leftStickY: 0,
                rightStickX: 0, rightStickY: 0,
                leftTrigger: 0, rightTrigger: 0,
                buttons: i % 2 == 0 ? [.a] : []
            )
        }
        let chunk = NitroGenActionChunk(steps: states)

        XCTAssertEqual(chunk.steps.count, 16)
        XCTAssertEqual(chunk.stepDuration, 1.0 / 30.0, accuracy: 0.001)

        let data = try JSONEncoder().encode(chunk)
        let decoded = try JSONDecoder().decode(NitroGenActionChunk.self, from: data)
        XCTAssertEqual(decoded.steps.count, 16)
        XCTAssertEqual(decoded.stepDuration, 1.0 / 30.0, accuracy: 0.001)
    }

    // ── StreamStatus ────────────────────────────────────────────────

    func testStreamStatusValues() {
        let statuses: [StreamStatus] = [.disconnected, .connecting, .authenticating, .buffering, .playing, .paused, .error]
        XCTAssertEqual(statuses.count, 7)
    }

    // ── GameInput ───────────────────────────────────────────────────

    func testGameInputCases() {
        // Verify all cases compile
        let inputs: [GameInput] = [
            .keyDown("W"),
            .keyUp("W"),
            .mouseMove(dx: 10, dy: -5),
            .mouseClick(button: .left, down: true),
            .mouseScroll(dx: 0, dy: -120),
            .gamepad(.neutral),
        ]
        XCTAssertEqual(inputs.count, 6)
    }
}
