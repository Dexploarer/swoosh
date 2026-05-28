// SwooshCloudGamingTests/GamepadBridgeTests.swift — GamepadBridge actor tests
// 0.5A – May 2026

#if canImport(GameController) && os(macOS)
import XCTest
@testable import SwooshCloudGaming

final class GamepadBridgeTests: XCTestCase {

    // ── Init ────────────────────────────────────────────────────────

    func testDefaultModeIsAgent() async {
        let bridge = GamepadBridge()
        let mode = await bridge.mode
        XCTAssertEqual(mode, .agent)
    }

    func testCustomInitMode() async {
        let bridge = GamepadBridge(mode: .physical)
        let mode = await bridge.mode
        XCTAssertEqual(mode, .physical)
    }

    // ── Mode switching ──────────────────────────────────────────────

    func testSetMode() async {
        let bridge = GamepadBridge(mode: .agent)
        await bridge.setMode(.mixed)
        let mode = await bridge.mode
        XCTAssertEqual(mode, .mixed)
    }

    // ── Virtual state injection ─────────────────────────────────────

    func testInjectVirtualState() async {
        let bridge = GamepadBridge(mode: .agent)

        let state = GamepadState(
            leftStickX: 0.8, leftStickY: -0.4,
            rightStickX: 0, rightStickY: 0,
            leftTrigger: 1.0, rightTrigger: 0,
            buttons: [.a, .b, .rightBumper]
        )
        await bridge.injectVirtualState(state)

        let effective = await bridge.effectiveState()
        XCTAssertEqual(effective.leftStickX, 0.8, accuracy: 0.001)
        XCTAssertEqual(effective.leftStickY, -0.4, accuracy: 0.001)
        XCTAssertEqual(effective.leftTrigger, 1.0, accuracy: 0.001)
        XCTAssertTrue(effective.buttons.contains(.a))
        XCTAssertTrue(effective.buttons.contains(.b))
        XCTAssertTrue(effective.buttons.contains(.rightBumper))
        XCTAssertFalse(effective.buttons.contains(.x))
    }

    func testAgentModeReturnsInjectedState() async {
        let bridge = GamepadBridge(mode: .agent)
        let custom = GamepadState(
            leftStickX: -1.0, leftStickY: 1.0,
            rightStickX: 0.5, rightStickY: -0.5,
            leftTrigger: 0.3, rightTrigger: 0.7,
            buttons: [.x, .y, .dpadUp, .start]
        )
        await bridge.injectVirtualState(custom)
        let result = await bridge.effectiveState()
        XCTAssertEqual(result, custom)
    }

    // ── Physical mode without controller ────────────────────────────

    func testPhysicalModeWithoutControllerReturnsNeutral() async {
        let bridge = GamepadBridge(mode: .physical)
        let state = await bridge.effectiveState()
        XCTAssertEqual(state, .neutral)
    }

    // ── Mixed mode ──────────────────────────────────────────────────

    func testMixedModeReturnsAgentWhenNoPhysical() async {
        let bridge = GamepadBridge(mode: .mixed)
        let agentState = GamepadState(
            leftStickX: 0.5, leftStickY: 0.5,
            rightStickX: 0, rightStickY: 0,
            leftTrigger: 0, rightTrigger: 0,
            buttons: [.a]
        )
        await bridge.injectVirtualState(agentState)
        let result = await bridge.effectiveState()
        XCTAssertEqual(result, agentState)
    }

    // ── No physical controller ──────────────────────────────────────

    func testNoPhysicalControllerConnected() async {
        let bridge = GamepadBridge()
        let connected = await bridge.isPhysicalConnected
        XCTAssertFalse(connected, "Expected no physical controller in test environment")
    }

    func testCurrentPhysicalStateNilWithoutController() async {
        let bridge = GamepadBridge()
        let state = await bridge.currentPhysicalState()
        XCTAssertNil(state)
    }

    // ── JavaScript shim ─────────────────────────────────────────────

    func testGamepadShimJSIsNonEmpty() {
        let js = GamepadBridge.gamepadShimJS
        XCTAssertFalse(js.isEmpty)
        XCTAssertTrue(js.contains("__swooshGamepad"), "Shim should create __swooshGamepad")
        XCTAssertTrue(js.contains("getGamepads"), "Shim should override getGamepads")
        XCTAssertTrue(js.contains("gamepadconnected"), "Shim should fire gamepadconnected event")
    }

    func testGamepadUpdateJSContainsState() async {
        let bridge = GamepadBridge(mode: .agent)
        let state = GamepadState(
            leftStickX: 0.5, leftStickY: 0,
            rightStickX: 0, rightStickY: 0,
            leftTrigger: 0, rightTrigger: 0,
            buttons: [.a]
        )
        await bridge.injectVirtualState(state)

        let js = await bridge.gamepadUpdateJS()

        // The JS updates __swooshGamepad axes and buttons
        XCTAssertTrue(js.contains("__swooshGamepad"), "Update JS should reference gamepad object")
        XCTAssertTrue(js.contains("axes[0]"), "Should update left stick X axis")
        XCTAssertTrue(js.contains("0.5"), "Should contain the stick X value 0.5")
        XCTAssertTrue(js.contains("buttons[0].pressed = true"), "A should be pressed")
    }

    func testGamepadUpdateJSButtonMapping() async {
        let bridge = GamepadBridge(mode: .agent)
        let state = GamepadState(
            leftStickX: -0.75, leftStickY: 0.3,
            rightStickX: 1.0, rightStickY: -1.0,
            leftTrigger: 0.9, rightTrigger: 0.1,
            buttons: [.a, .b, .leftBumper, .dpadUp]
        )
        await bridge.injectVirtualState(state)

        let js = await bridge.gamepadUpdateJS()

        // A = buttons[0], B = buttons[1], LB = buttons[4], dpadUp = buttons[12]
        XCTAssertTrue(js.contains("buttons[0].pressed = true"), "A pressed")
        XCTAssertTrue(js.contains("buttons[1].pressed = true"), "B pressed")
        XCTAssertTrue(js.contains("buttons[4].pressed = true"), "LB pressed")
        XCTAssertTrue(js.contains("buttons[12].pressed = true"), "D-pad Up pressed")

        // X = buttons[2], Y = buttons[3] should NOT be pressed
        XCTAssertTrue(js.contains("buttons[2].pressed = false"), "X not pressed")
        XCTAssertTrue(js.contains("buttons[3].pressed = false"), "Y not pressed")

        // Trigger values
        XCTAssertTrue(js.contains("buttons[6].value = 0.9"), "LT value")
        XCTAssertTrue(js.contains("buttons[6].pressed = true"), "LT pressed (>0.5)")
        XCTAssertTrue(js.contains("buttons[7].value = 0.1"), "RT value")
        XCTAssertTrue(js.contains("buttons[7].pressed = false"), "RT not pressed (<0.5)")
    }

    // ── Monitoring lifecycle ────────────────────────────────────────

    func testStartStopMonitoringDoesNotCrash() async {
        let bridge = GamepadBridge()
        await bridge.startMonitoring()
        try? await Task.sleep(for: .milliseconds(100))
        await bridge.stopMonitoring()
    }

    // ── Rapid injection ─────────────────────────────────────────────

    func testRapidStateUpdates() async {
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

        let final_ = await bridge.effectiveState()
        XCTAssertEqual(final_.leftStickX, sin(29 * 0.2), accuracy: 0.001)
    }
}
#endif
