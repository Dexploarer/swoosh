// SwooshCloudGaming/GamepadBridge.swift — Apple GameController ↔ GamepadState bridge
//
// Bridges real physical controllers (via Apple's GameController framework)
// to our GamepadState type. Supports three modes: physical passthrough,
// agent-controlled (NitroGen), and mixed (agent + human override).
// 0.5A – May 2026

#if canImport(GameController)
import GameController
import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Control mode
// ═══════════════════════════════════════════════════════════════════

/// Who is driving the controller input.
public enum GamepadControlMode: String, Codable, Sendable {
    /// Physical controller passthrough — human plays.
    case physical
    /// AI agent controls — NitroGen drives the gamepad.
    case agent
    /// Mixed — NitroGen drives, but physical input overrides in real time.
    case mixed
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - GamepadBridge
// ═══════════════════════════════════════════════════════════════════

public actor GamepadBridge {
    private var physicalController: GCController?
    private var agentState: GamepadState = .neutral
    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?

    public private(set) var mode: GamepadControlMode
    public private(set) var isPhysicalConnected: Bool = false

    public init(mode: GamepadControlMode = .agent) {
        self.mode = mode
    }

    // ── Lifecycle ────────────────────────────────────────────────

    /// Start monitoring for physical controller connections.
    public func startMonitoring() {
        nonisolated(unsafe) let weakSelf = self

        connectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil, queue: .main
        ) { notification in
            guard let controller = notification.object as? GCController else { return }
            nonisolated(unsafe) let c = controller
            Task { await weakSelf.controllerConnected(c) }
        }

        disconnectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil, queue: .main
        ) { _ in
            Task { await weakSelf.controllerDisconnected() }
        }

        // Check if a controller is already connected
        if let existing = GCController.controllers().first {
            Task { await controllerConnected(existing) }
        }

        GCController.startWirelessControllerDiscovery {}
    }

    /// Stop monitoring.
    public func stopMonitoring() {
        if let obs = connectObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = disconnectObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        GCController.stopWirelessControllerDiscovery()
        physicalController = nil
        isPhysicalConnected = false
    }

    // ── Mode switching ───────────────────────────────────────────

    public func setMode(_ newMode: GamepadControlMode) {
        self.mode = newMode
    }

    // ── State access ─────────────────────────────────────────────

    /// Get the current physical controller state (if connected).
    public func currentPhysicalState() -> GamepadState? {
        guard let pad = physicalController?.extendedGamepad else { return nil }
        return Self.mapExtendedGamepad(pad)
    }

    /// Set the AI agent's desired gamepad state.
    public func injectVirtualState(_ state: GamepadState) {
        self.agentState = state
    }

    /// Get the effective gamepad state based on current mode.
    public func effectiveState() -> GamepadState {
        switch mode {
        case .physical:
            return currentPhysicalState() ?? .neutral
        case .agent:
            return agentState
        case .mixed:
            // Physical overrides agent when any input is detected
            if let physical = currentPhysicalState(), physical != .neutral {
                return physical
            }
            return agentState
        }
    }

    // ── JavaScript gamepad shim ──────────────────────────────────

    /// Generate JavaScript to update the virtual gamepad in a WKWebView.
    /// Call this at ~60Hz via `webView.evaluateJavaScript()`.
    public func gamepadUpdateJS() -> String {
        let state = effectiveState()
        return """
        if (window.__swooshGamepad) {
            window.__swooshGamepad.axes[0] = \(state.leftStickX);
            window.__swooshGamepad.axes[1] = \(state.leftStickY);
            window.__swooshGamepad.axes[2] = \(state.rightStickX);
            window.__swooshGamepad.axes[3] = \(state.rightStickY);
            window.__swooshGamepad.buttons[0].pressed = \(state.buttons.contains(.a));
            window.__swooshGamepad.buttons[1].pressed = \(state.buttons.contains(.b));
            window.__swooshGamepad.buttons[2].pressed = \(state.buttons.contains(.x));
            window.__swooshGamepad.buttons[3].pressed = \(state.buttons.contains(.y));
            window.__swooshGamepad.buttons[4].pressed = \(state.buttons.contains(.leftBumper));
            window.__swooshGamepad.buttons[5].pressed = \(state.buttons.contains(.rightBumper));
            window.__swooshGamepad.buttons[6].value = \(state.leftTrigger);
            window.__swooshGamepad.buttons[6].pressed = \(state.leftTrigger > 0.5);
            window.__swooshGamepad.buttons[7].value = \(state.rightTrigger);
            window.__swooshGamepad.buttons[7].pressed = \(state.rightTrigger > 0.5);
            window.__swooshGamepad.buttons[8].pressed = \(state.buttons.contains(.back));
            window.__swooshGamepad.buttons[9].pressed = \(state.buttons.contains(.start));
            window.__swooshGamepad.buttons[10].pressed = \(state.buttons.contains(.leftThumb));
            window.__swooshGamepad.buttons[11].pressed = \(state.buttons.contains(.rightThumb));
            window.__swooshGamepad.buttons[12].pressed = \(state.buttons.contains(.dpadUp));
            window.__swooshGamepad.buttons[13].pressed = \(state.buttons.contains(.dpadDown));
            window.__swooshGamepad.buttons[14].pressed = \(state.buttons.contains(.dpadLeft));
            window.__swooshGamepad.buttons[15].pressed = \(state.buttons.contains(.dpadRight));
            window.__swooshGamepad.buttons[16].pressed = \(state.buttons.contains(.guide));
            window.__swooshGamepad.timestamp = performance.now();
        }
        """
    }

    /// JavaScript shim to install at page load that creates a virtual gamepad
    /// visible to the standard W3C Gamepad API.
    public static let gamepadShimJS: String = """
    (function() {
        function makeButton() { return { pressed: false, touched: false, value: 0.0 }; }
        window.__swooshGamepad = {
            id: 'Swoosh Virtual Xbox Controller (XInput)',
            index: 0,
            connected: true,
            mapping: 'standard',
            axes: [0.0, 0.0, 0.0, 0.0],
            buttons: Array.from({ length: 17 }, makeButton),
            timestamp: performance.now(),
            vibrationActuator: null
        };
        const origGetGamepads = navigator.getGamepads.bind(navigator);
        navigator.getGamepads = function() {
            const real = origGetGamepads();
            const result = [window.__swooshGamepad];
            for (let i = 0; i < real.length; i++) {
                if (real[i]) result.push(real[i]);
            }
            return result;
        };
        window.dispatchEvent(new Event('gamepadconnected'));
    })();
    """

    // ── Private ──────────────────────────────────────────────────

    private func controllerConnected(_ controller: GCController) {
        self.physicalController = controller
        self.isPhysicalConnected = true
    }

    private func controllerDisconnected() {
        self.physicalController = nil
        self.isPhysicalConnected = false
    }

    private static func mapExtendedGamepad(_ pad: GCExtendedGamepad) -> GamepadState {
        var buttons = GamepadButtons()

        if pad.buttonA.isPressed       { buttons.insert(.a) }
        if pad.buttonB.isPressed       { buttons.insert(.b) }
        if pad.buttonX.isPressed       { buttons.insert(.x) }
        if pad.buttonY.isPressed       { buttons.insert(.y) }
        if pad.dpad.up.isPressed       { buttons.insert(.dpadUp) }
        if pad.dpad.down.isPressed     { buttons.insert(.dpadDown) }
        if pad.dpad.left.isPressed     { buttons.insert(.dpadLeft) }
        if pad.dpad.right.isPressed    { buttons.insert(.dpadRight) }
        if pad.leftShoulder.isPressed  { buttons.insert(.leftBumper) }
        if pad.rightShoulder.isPressed { buttons.insert(.rightBumper) }
        if pad.leftThumbstickButton?.isPressed == true  { buttons.insert(.leftThumb) }
        if pad.rightThumbstickButton?.isPressed == true  { buttons.insert(.rightThumb) }
        if pad.buttonMenu.isPressed    { buttons.insert(.start) }
        if pad.buttonOptions?.isPressed == true { buttons.insert(.back) }
        if pad.buttonHome?.isPressed == true    { buttons.insert(.guide) }

        return GamepadState(
            leftStickX:  pad.leftThumbstick.xAxis.value,
            leftStickY:  pad.leftThumbstick.yAxis.value,
            rightStickX: pad.rightThumbstick.xAxis.value,
            rightStickY: pad.rightThumbstick.yAxis.value,
            leftTrigger:  pad.leftTrigger.value,
            rightTrigger: pad.rightTrigger.value,
            buttons: buttons
        )
    }
}
#endif
