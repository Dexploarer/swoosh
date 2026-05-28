// SwooshCloudGaming/GameStreamAdapter.swift — Unified game stream protocol
//
// Defines the protocol and types that abstract over web-based (WKWebView)
// and native (ScreenCaptureKit) game streaming sources. NitroGen talks
// only to this interface — it doesn't know or care where frames come from.
// 0.5A – May 2026

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// ═══════════════════════════════════════════════════════════════════
// MARK: - Gamepad state (matches NitroGen output format)
// ═══════════════════════════════════════════════════════════════════

/// Full Xbox-layout gamepad state. NitroGen outputs this directly:
/// 2× joystick vectors (continuous 2D, -1…1) + 17 binary buttons.
public struct GamepadState: Codable, Sendable, Equatable {
    // ── Joysticks ────────────────────────────────────────────────
    /// Left stick X axis: -1.0 (left) to 1.0 (right)
    public var leftStickX: Float
    /// Left stick Y axis: -1.0 (down) to 1.0 (up)
    public var leftStickY: Float
    /// Right stick X axis: -1.0 (left) to 1.0 (right)
    public var rightStickX: Float
    /// Right stick Y axis: -1.0 (down) to 1.0 (up)
    public var rightStickY: Float

    // ── Triggers ─────────────────────────────────────────────────
    /// Left trigger: 0.0 (released) to 1.0 (fully pressed)
    public var leftTrigger: Float
    /// Right trigger: 0.0 (released) to 1.0 (fully pressed)
    public var rightTrigger: Float

    // ── Buttons ──────────────────────────────────────────────────
    public var buttons: GamepadButtons

    public init(
        leftStickX: Float = 0, leftStickY: Float = 0,
        rightStickX: Float = 0, rightStickY: Float = 0,
        leftTrigger: Float = 0, rightTrigger: Float = 0,
        buttons: GamepadButtons = []
    ) {
        self.leftStickX = leftStickX
        self.leftStickY = leftStickY
        self.rightStickX = rightStickX
        self.rightStickY = rightStickY
        self.leftTrigger = leftTrigger
        self.rightTrigger = rightTrigger
        self.buttons = buttons
    }

    /// Neutral state — all sticks centered, all buttons released.
    public static let neutral = GamepadState()
}

/// Xbox-layout button bitmask. 17 buttons matching NitroGen's output.
public struct GamepadButtons: OptionSet, Codable, Sendable, Equatable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let a              = GamepadButtons(rawValue: 1 << 0)
    public static let b              = GamepadButtons(rawValue: 1 << 1)
    public static let x              = GamepadButtons(rawValue: 1 << 2)
    public static let y              = GamepadButtons(rawValue: 1 << 3)
    public static let dpadUp         = GamepadButtons(rawValue: 1 << 4)
    public static let dpadDown       = GamepadButtons(rawValue: 1 << 5)
    public static let dpadLeft       = GamepadButtons(rawValue: 1 << 6)
    public static let dpadRight      = GamepadButtons(rawValue: 1 << 7)
    public static let leftBumper     = GamepadButtons(rawValue: 1 << 8)
    public static let rightBumper    = GamepadButtons(rawValue: 1 << 9)
    public static let leftThumb      = GamepadButtons(rawValue: 1 << 10)
    public static let rightThumb     = GamepadButtons(rawValue: 1 << 11)
    public static let start          = GamepadButtons(rawValue: 1 << 12)
    public static let back           = GamepadButtons(rawValue: 1 << 13)  // aka "select" / "view"
    public static let guide          = GamepadButtons(rawValue: 1 << 14)  // Xbox button
    public static let leftTrigger    = GamepadButtons(rawValue: 1 << 15)  // digital trigger
    public static let rightTrigger   = GamepadButtons(rawValue: 1 << 16)  // digital trigger
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Game input (all possible input events)
// ═══════════════════════════════════════════════════════════════════

/// Input events the agent can send to a game.
public enum GameInput: Codable, Sendable {
    case keyDown(String)
    case keyUp(String)
    case mouseMove(dx: Double, dy: Double)
    case mouseClick(button: MouseButton, down: Bool)
    case mouseScroll(dx: Double, dy: Double)
    case gamepad(GamepadState)
}

public enum MouseButton: String, Codable, Sendable {
    case left, right, middle
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Stream info
// ═══════════════════════════════════════════════════════════════════

/// Metadata about the active game stream.
public struct StreamInfo: Sendable {
    public let source: GameSource
    public let resolution: CGSize?
    public let estimatedFPS: Double
    public let latencyMs: Double?

    public init(source: GameSource, resolution: CGSize? = nil,
                estimatedFPS: Double = 0, latencyMs: Double? = nil) {
        self.source = source
        self.resolution = resolution
        self.estimatedFPS = estimatedFPS
        self.latencyMs = latencyMs
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Stream status
// ═══════════════════════════════════════════════════════════════════

public enum StreamStatus: String, Sendable {
    case disconnected
    case connecting
    case authenticating
    case buffering
    case playing
    case paused
    case error
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - GameStreamProviding protocol
// ═══════════════════════════════════════════════════════════════════

/// Unified interface for both web-based and native game streams.
/// NitroGen talks to this — it doesn't know if the source is
/// Xbox Cloud Gaming via WKWebView or Steam via ScreenCaptureKit.
public protocol GameStreamProviding: Sendable {
    /// Capture the current game frame as JPEG bytes.
    func captureFrame() async throws -> Data

    /// Send an input event to the game.
    func sendInput(_ input: GameInput) async throws

    /// Whether the stream is currently connected and active.
    var isConnected: Bool { get async }

    /// Current stream status.
    var status: StreamStatus { get async }

    /// Metadata about the stream.
    var info: StreamInfo { get async }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - NitroGen action chunk
// ═══════════════════════════════════════════════════════════════════

/// A 16-step action chunk as output by NitroGen.
/// Each step contains a full gamepad state.
public struct NitroGenActionChunk: Codable, Sendable {
    /// 16 sequential gamepad states to execute over the next ~500ms.
    public let steps: [GamepadState]

    /// Duration per step in seconds (default: 1/30 = ~33ms at 30 FPS).
    public let stepDuration: Double

    public init(steps: [GamepadState], stepDuration: Double = 1.0 / 30.0) {
        precondition(steps.count == 16, "NitroGen outputs exactly 16 action steps")
        self.steps = steps
        self.stepDuration = stepDuration
    }
}
