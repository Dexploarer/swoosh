// SwooshCloudGamingTests/IntegrationFlowTests.swift — End-to-end gaming pipeline tests
// 0.5A – May 2026

#if os(macOS)
import XCTest
@testable import SwooshCloudGaming

/// Tests the full agent gaming flow:
/// 1. Service selection → bridge creation
/// 2. Frame capture → NitroGen input format
/// 3. NitroGen output → gamepad state application
/// 4. Gamepad state → JS shim / CGEvent injection
final class IntegrationFlowTests: XCTestCase {

    // ── Service → Bridge creation ───────────────────────────────────

    func testWebServiceCreatesCorrectBridgeType() {
        // Each web service should be wrappable in a GameSource
        let xboxSource = GameSource.web(.xboxCloud)
        let gfnSource = GameSource.web(.geforceNow)
        let lunaSource = GameSource.web(.amazonLuna)

        // Verify we can switch on all source types
        for source in [xboxSource, gfnSource, lunaSource] {
            switch source {
            case .web(let svc):
                XCTAssertFalse(svc.displayName.isEmpty)
            case .native:
                XCTFail("Expected web source")
            }
        }
    }

    func testNativeSourceCreatesCorrectBridgeType() {
        let sources: [NativeGameSource] = [.greenlight, .steamLink, .playstation, .localWindow]
        for ns in sources {
            let source = GameSource.native(ns)
            switch source {
            case .web:
                XCTFail("Expected native source")
            case .native(let actual):
                XCTAssertEqual(actual, ns)
            }
        }
    }

    // ── NitroGen I/O format ─────────────────────────────────────────

    func testNitroGenInputFrameSize() {
        // NitroGen expects 256×256 RGB frames
        // Verify our constants match
        // The capture methods resize to 256×256 — this test verifies
        // the action chunk structure that consumes those frames.
        let chunk = NitroGenActionChunk(
            steps: Array(repeating: .neutral, count: 16)
        )
        XCTAssertEqual(chunk.steps.count, 16, "NitroGen outputs 16-step chunks")
        XCTAssertEqual(chunk.stepDuration, 1.0 / 30.0, accuracy: 0.001, "Default step duration is 1/30s")
    }

    func testNitroGenOutputAppliedToGamepad() async {
        #if canImport(GameController)
        let bridge = GamepadBridge(mode: .agent)

        // Simulate NitroGen outputting a 16-step action chunk
        let chunk = NitroGenActionChunk(
            steps: (0..<16).map { i in
                GamepadState(
                    leftStickX: Float(i) / 15.0 * 2.0 - 1.0,
                    leftStickY: 0,
                    rightStickX: 0,
                    rightStickY: 0,
                    leftTrigger: i < 8 ? 0 : 1.0,
                    rightTrigger: 0,
                    buttons: i == 5 ? [.a] : []
                )
            }
        )

        // Apply each step and verify the bridge reflects it
        for (i, step) in chunk.steps.enumerated() {
            await bridge.injectVirtualState(step)
            let effective = await bridge.effectiveState()
            XCTAssertEqual(effective.leftStickX, step.leftStickX, accuracy: 0.001,
                "Frame \(i) left stick X mismatch")
            XCTAssertEqual(effective.leftTrigger, step.leftTrigger, accuracy: 0.001,
                "Frame \(i) left trigger mismatch")
        }
        #endif
    }

    // ── GamepadState → JS shim output ───────────────────────────────

    #if canImport(GameController)
    func testGamepadStateProducesCorrectJS() async {
        let bridge = GamepadBridge(mode: .agent)

        // Inject a complex state
        let state = GamepadState(
            leftStickX: -0.75, leftStickY: 0.3,
            rightStickX: 1.0, rightStickY: -1.0,
            leftTrigger: 0.9, rightTrigger: 0.1,
            buttons: [.a, .b, .leftBumper, .dpadUp]
        )
        await bridge.injectVirtualState(state)

        let js = await bridge.gamepadUpdateJS()

        // Verify axis values appear
        XCTAssertTrue(js.contains("-0.75"), "Should contain left stick X")
        XCTAssertTrue(js.contains("0.3"), "Should contain left stick Y")
        XCTAssertTrue(js.contains("1.0"), "Should contain right stick X")

        // Verify button states
        // buttons[0] = A = true
        // buttons[1] = B = true
        // buttons[4] = LB = true
        // buttons[12] = dpadUp = true
        XCTAssertTrue(js.contains("buttons[0].pressed = true"), "A should be pressed")
        XCTAssertTrue(js.contains("buttons[1].pressed = true"), "B should be pressed")
        XCTAssertTrue(js.contains("buttons[4].pressed = true"), "LB should be pressed")
        XCTAssertTrue(js.contains("buttons[12].pressed = true"), "D-pad Up should be pressed")

        // Verify unpressed buttons
        XCTAssertTrue(js.contains("buttons[2].pressed = false"), "X should not be pressed")
        XCTAssertTrue(js.contains("buttons[3].pressed = false"), "Y should not be pressed")

        // Verify trigger values
        XCTAssertTrue(js.contains("buttons[6].value = 0.9"), "LT value should be 0.9")
        XCTAssertTrue(js.contains("buttons[6].pressed = true"), "LT should be pressed (> 0.5)")
        XCTAssertTrue(js.contains("buttons[7].value = 0.1"), "RT value should be 0.1")
        XCTAssertTrue(js.contains("buttons[7].pressed = false"), "RT should not be pressed (< 0.5)")
    }
    #endif

    // ── Full pipeline serialization ─────────────────────────────────

    func testFullPipelineStateSerialization() throws {
        // Simulate the full data path:
        // 1. Agent kernel sends GamepadState
        // 2. State is serialized over wire (JSON)
        // 3. Deserialized and applied to bridge
        // 4. Bridge generates JS update

        let originalState = GamepadState(
            leftStickX: 0.42, leftStickY: -0.88,
            rightStickX: 0.0, rightStickY: 0.33,
            leftTrigger: 0.75, rightTrigger: 0.0,
            buttons: [.a, .x, .rightBumper, .dpadLeft]
        )

        // Serialize
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(originalState)
        let json = String(data: data, encoding: .utf8)!

        // Verify JSON structure
        XCTAssertTrue(json.contains("leftStickX"))
        XCTAssertTrue(json.contains("buttons"))
        XCTAssertTrue(json.contains("0.42"))

        // Deserialize
        let decoded = try JSONDecoder().decode(GamepadState.self, from: data)
        XCTAssertEqual(decoded, originalState)
    }

    // ── Multiple rapid state updates ────────────────────────────────

    #if canImport(GameController)
    func testRapidStateUpdates() async {
        // Simulate 30 FPS state injection (what NitroGen does)
        let bridge = GamepadBridge(mode: .agent)

        for i in 0..<30 {
            let state = GamepadState(
                leftStickX: sin(Float(i) * 0.2),
                leftStickY: cos(Float(i) * 0.2),
                rightStickX: 0,
                rightStickY: 0,
                leftTrigger: 0,
                rightTrigger: 0,
                buttons: i % 10 == 0 ? [.a] : []
            )
            await bridge.injectVirtualState(state)
        }

        // Verify the last state stuck
        let final = await bridge.effectiveState()
        XCTAssertEqual(final.leftStickX, sin(29 * 0.2), accuracy: 0.001)
    }
    #endif
}
#endif
