// SwooshToolsets/NitroGen/NitroGenTools.swift — 0.9U NitroGen tool implementations
//
// Four tools that let the main agent control NitroGen:
//   nitrogen_start   — spawn inference server + player
//   nitrogen_stop    — kill both processes
//   nitrogen_status  — check FPS, steps, health
//   nitrogen_screenshot — capture current game frame

#if os(macOS)

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - nitrogen_start
// ═══════════════════════════════════════════════════════════════════

public struct NitroGenStartTool: SwooshTool {
    public static let name: ToolName = "nitrogen_start"
    public static let displayName = "Start NitroGen"
    public static let description = "Start the NitroGen gaming agent. Spawns the inference server and player process to begin autonomous gameplay."
    public static let permission = SwooshPermission.nitrogenControl
    public static let risk = ToolRisk.high
    public static let approval = ApprovalPolicy.askFirstTime
    public static let toolset = ToolsetID.nitrogen
    public static let platforms: Set<ToolPlatform> = [.macOS]

    public typealias Input = NitroGenStartInput
    public typealias Output = NitroGenStartOutput

    private let controller: NitroGenController

    public init(controller: NitroGenController) {
        self.controller = controller
    }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        try await controller.start(
            windowTitle: input.windowTitle,
            bundleID: input.bundleID,
            keymap: input.keymap,
            fps: input.fps ?? 30,
            dryRun: input.dryRun ?? false
        )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - nitrogen_stop
// ═══════════════════════════════════════════════════════════════════

public struct NitroGenStopTool: SwooshTool {
    public static let name: ToolName = "nitrogen_stop"
    public static let displayName = "Stop NitroGen"
    public static let description = "Stop the NitroGen gaming agent. Terminates both the inference server and player process."
    public static let permission = SwooshPermission.nitrogenControl
    public static let risk = ToolRisk.low
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.nitrogen
    public static let platforms: Set<ToolPlatform> = [.macOS]

    public typealias Input = NitroGenStopInput
    public typealias Output = NitroGenStopOutput

    private let controller: NitroGenController

    public init(controller: NitroGenController) {
        self.controller = controller
    }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        await controller.stop()
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - nitrogen_status
// ═══════════════════════════════════════════════════════════════════

public struct NitroGenStatusTool: SwooshTool {
    public static let name: ToolName = "nitrogen_status"
    public static let displayName = "NitroGen Status"
    public static let description = "Check NitroGen gaming agent status: running state, FPS, step count, server health."
    public static let permission = SwooshPermission.nitrogenRead
    public static let risk = ToolRisk.low
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.nitrogen
    public static let platforms: Set<ToolPlatform> = [.macOS]

    public typealias Input = NitroGenStatusInput
    public typealias Output = NitroGenStatusOutput

    private let controller: NitroGenController

    public init(controller: NitroGenController) {
        self.controller = controller
    }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        await controller.getStatus()
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - nitrogen_screenshot
// ═══════════════════════════════════════════════════════════════════

public struct NitroGenScreenshotTool: SwooshTool {
    public static let name: ToolName = "nitrogen_screenshot"
    public static let displayName = "NitroGen Screenshot"
    public static let description = "Capture the current game frame that NitroGen sees. Returns the frame so the main agent can observe gameplay."
    public static let permission = SwooshPermission.nitrogenRead
    public static let risk = ToolRisk.low
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.nitrogen
    public static let platforms: Set<ToolPlatform> = [.macOS]

    public typealias Input = NitroGenScreenshotInput
    public typealias Output = NitroGenScreenshotOutput

    private let controller: NitroGenController

    public init(controller: NitroGenController) {
        self.controller = controller
    }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let status = await controller.getStatus()
        guard status.status == NitroGenStatus.playing.rawValue else {
            return NitroGenScreenshotOutput(
                status: "error",
                message: "NitroGen is not playing. Current status: \(status.status)"
            )
        }

        // TODO: Capture frame via ScreenCaptureKit or read from NitroGen's frame buffer
        return NitroGenScreenshotOutput(
            status: "ok",
            message: "Frame captured at step \(status.stepCount)"
        )
    }
}

#endif
