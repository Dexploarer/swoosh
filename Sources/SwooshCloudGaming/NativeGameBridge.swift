// SwooshCloudGaming/NativeGameBridge.swift — ScreenCaptureKit + CGEvent bridge
//
// Captures frames from native macOS apps (Greenlight, Steam Link, etc.)
// via ScreenCaptureKit and injects input via CGEvent. This is the primary
// path for the Greenlight → NitroGen → Xbox Cloud Gaming pipeline.
// 0.5A – May 2026

#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
import CoreGraphics
import CoreMedia
import Foundation
import AppKit

// ═══════════════════════════════════════════════════════════════════
// MARK: - NativeGameBridge
// ═══════════════════════════════════════════════════════════════════

public actor NativeGameBridge: GameStreamProviding {
    private let windowID: CGWindowID
    private let source: NativeGameSource
    private var stream: SCStream?
    private var delegate: FrameGrabber?
    private var _status: StreamStatus = .disconnected
    private var frameCount: Int = 0
    private var startTime: Date?

    // ── Init ─────────────────────────────────────────────────────

    public init(windowID: CGWindowID, source: NativeGameSource) {
        self.windowID = windowID
        self.source = source
    }

    // ── GameStreamProviding ──────────────────────────────────────

    public var isConnected: Bool { _status == .playing }
    public var status: StreamStatus { _status }

    public var info: StreamInfo {
        let fps: Double
        if let start = startTime, frameCount > 0 {
            let elapsed = Date().timeIntervalSince(start)
            fps = elapsed > 0 ? Double(frameCount) / elapsed : 0
        } else {
            fps = 0
        }
        return StreamInfo(
            source: .native(source),
            estimatedFPS: fps
        )
    }

    /// Start the capture stream.
    public func startCapture() async throws {
        _status = .connecting

        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )

        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            _status = .error
            throw NativeGameError.windowNotFound(windowID)
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = 1280
        config.height = 720
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30) // 30 FPS
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false

        let grabber = FrameGrabber()
        self.delegate = grabber

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(grabber, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
        try await stream.startCapture()

        self.stream = stream
        self.startTime = Date()
        self._status = .playing
    }

    /// Stop the capture stream.
    public func stopCapture() async throws {
        if let stream {
            try await stream.stopCapture()
        }
        self.stream = nil
        self.delegate = nil
        self._status = .disconnected
    }

    public func captureFrame() async throws -> Data {
        guard let delegate else {
            throw NativeGameError.notCapturing
        }
        guard let buffer = delegate.latestBuffer else {
            throw NativeGameError.noFrameAvailable
        }
        frameCount += 1
        return try Self.jpegData(from: buffer)
    }

    public func sendInput(_ input: GameInput) async throws {
        switch input {
        case .keyDown(let key):
            try Self.postKeyEvent(key: key, down: true)
        case .keyUp(let key):
            try Self.postKeyEvent(key: key, down: false)
        case .mouseMove(let dx, let dy):
            try Self.postMouseMove(dx: dx, dy: dy)
        case .mouseClick(let button, let down):
            try Self.postMouseClick(button: button, down: down)
        case .mouseScroll(let dx, let dy):
            try Self.postMouseScroll(dx: dx, dy: dy)
        case .gamepad(let state):
            // Map gamepad to keyboard for native apps without controller support
            try Self.postGamepadAsKeyboard(state)
        }
    }

    // ── Window discovery ─────────────────────────────────────────

    /// Find windows matching a native game source's known bundle identifiers.
    public static func discoverWindows(
        for source: NativeGameSource
    ) async throws -> [(id: CGWindowID, title: String, bundleID: String)] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )

        let bundleIDs = Set(source.bundleIdentifiers)
        if bundleIDs.isEmpty {
            // Return all on-screen windows for .localWindow
            return content.windows.compactMap { window in
                guard let title = window.title, !title.isEmpty else { return nil }
                let bid = window.owningApplication?.bundleIdentifier ?? ""
                return (id: window.windowID, title: title, bundleID: bid)
            }
        }

        return content.windows.compactMap { window in
            guard let bid = window.owningApplication?.bundleIdentifier,
                  bundleIDs.contains(bid) else { return nil }
            let title = window.title ?? "Untitled"
            return (id: window.windowID, title: title, bundleID: bid)
        }
    }

    // ── Frame conversion ─────────────────────────────────────────

    private static func jpegData(from buffer: CMSampleBuffer, quality: CGFloat = 0.6) throws -> Data {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else {
            throw NativeGameError.frameConversionFailed
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

        guard let data = context.jpegRepresentation(
            of: ciImage,
            colorSpace: colorSpace
        ) else {
            throw NativeGameError.frameConversionFailed
        }

        return data
    }

    // ── CGEvent input injection ──────────────────────────────────

    private static func postKeyEvent(key: String, down: Bool) throws {
        let keyCode = Self.virtualKeyCode(for: key)
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: down
        ) else {
            throw NativeGameError.inputInjectionFailed
        }
        event.post(tap: .cgSessionEventTap)
    }

    private static func postMouseMove(dx: Double, dy: Double) throws {
        let currentPos = CGEvent(source: nil)?.location ?? .zero
        let newPos = CGPoint(x: currentPos.x + dx, y: currentPos.y + dy)

        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: newPos,
            mouseButton: .left
        ) else {
            throw NativeGameError.inputInjectionFailed
        }
        event.post(tap: .cgSessionEventTap)
    }

    private static func postMouseClick(button: MouseButton, down: Bool) throws {
        let currentPos = CGEvent(source: nil)?.location ?? .zero
        let (mouseType, cgButton): (CGEventType, CGMouseButton) = switch button {
        case .left:   (down ? .leftMouseDown : .leftMouseUp, .left)
        case .right:  (down ? .rightMouseDown : .rightMouseUp, .right)
        case .middle: (down ? .otherMouseDown : .otherMouseUp, .center)
        }

        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: mouseType,
            mouseCursorPosition: currentPos,
            mouseButton: cgButton
        ) else {
            throw NativeGameError.inputInjectionFailed
        }
        event.post(tap: .cgSessionEventTap)
    }

    private static func postMouseScroll(dx: Double, dy: Double) throws {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(dy),
            wheel2: Int32(dx),
            wheel3: 0
        ) else {
            throw NativeGameError.inputInjectionFailed
        }
        event.post(tap: .cgSessionEventTap)
    }

    /// Map gamepad state to WASD + arrow keys for apps without native controller.
    private static func postGamepadAsKeyboard(_ state: GamepadState) throws {
        // Left stick → WASD
        let threshold: Float = 0.3
        try postKeyEvent(key: "w", down: state.leftStickY > threshold)
        try postKeyEvent(key: "s", down: state.leftStickY < -threshold)
        try postKeyEvent(key: "a", down: state.leftStickX < -threshold)
        try postKeyEvent(key: "d", down: state.leftStickX > threshold)

        // Face buttons → common keys
        if state.buttons.contains(.a) { try postKeyEvent(key: "space", down: true) }
        if state.buttons.contains(.b) { try postKeyEvent(key: "escape", down: true) }
    }

    // ── Key code mapping ─────────────────────────────────────────

    private static func virtualKeyCode(for key: String) -> CGKeyCode {
        switch key.lowercased() {
        case "a": return 0x00
        case "s": return 0x01
        case "d": return 0x02
        case "w": return 0x0D
        case "space": return 0x31
        case "escape", "esc": return 0x35
        case "return", "enter": return 0x24
        case "tab": return 0x30
        case "shift": return 0x38
        case "control", "ctrl": return 0x3B
        case "option", "alt": return 0x3A
        case "up": return 0x7E
        case "down": return 0x7D
        case "left": return 0x7B
        case "right": return 0x7C
        case "e": return 0x0E
        case "r": return 0x0F
        case "f": return 0x03
        case "q": return 0x0C
        default: return 0x00
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Frame grabber (SCStreamOutput delegate)
// ═══════════════════════════════════════════════════════════════════

private final class FrameGrabber: NSObject, SCStreamOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var _latestBuffer: CMSampleBuffer?

    var latestBuffer: CMSampleBuffer? {
        lock.withLock { _latestBuffer }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        lock.withLock { _latestBuffer = sampleBuffer }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Errors
// ═══════════════════════════════════════════════════════════════════

public enum NativeGameError: Error, LocalizedError {
    case windowNotFound(CGWindowID)
    case notCapturing
    case noFrameAvailable
    case frameConversionFailed
    case inputInjectionFailed

    public var errorDescription: String? {
        switch self {
        case .windowNotFound(let id): "Window \(id) not found"
        case .notCapturing:           "Capture not started"
        case .noFrameAvailable:       "No frame available yet"
        case .frameConversionFailed:  "Failed to convert frame to JPEG"
        case .inputInjectionFailed:   "Failed to inject input event"
        }
    }
}
#endif
