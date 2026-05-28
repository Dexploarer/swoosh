// SwooshUI/Gaming/GamingAgentSendHandler.swift — Gaming-enriched agent send — 0.9U
//
// Builds a context-enriched AgentSendHandler for the gaming pane.
// When the user speaks or types to the orb, this handler prepends
// gaming context (platform, stream status, NitroGen state, keymaps)
// before routing through the configured provider via the daemon API
// or local AgentKernel.
//
// Falls back to a demo handler when the daemon isn't reachable —
// the demo handler still enriches context and echoes with gaming
// awareness so the UI is always responsive.

#if os(macOS)

import Foundation
import SwooshCloudGaming

// ═══════════════════════════════════════════════════════════════════
// MARK: - Gaming context
// ═══════════════════════════════════════════════════════════════════

/// Snapshot of the gaming pane's current state, passed to the agent
/// as contextual knowledge alongside the user's message.
public struct GamingContext: Sendable {
    public let selectedPlatform: String?
    public let streamStatus: StreamStatus
    public let isNitroGenRunning: Bool
    public let currentFPS: Double
    public let stepCount: Int
    public let windowTitle: String?
    public let bundleID: String?
    public let availableKeymaps: [String]

    public init(
        selectedPlatform: String? = nil,
        streamStatus: StreamStatus = .disconnected,
        isNitroGenRunning: Bool = false,
        currentFPS: Double = 0,
        stepCount: Int = 0,
        windowTitle: String? = nil,
        bundleID: String? = nil,
        availableKeymaps: [String] = []
    ) {
        self.selectedPlatform = selectedPlatform
        self.streamStatus = streamStatus
        self.isNitroGenRunning = isNitroGenRunning
        self.currentFPS = currentFPS
        self.stepCount = stepCount
        self.windowTitle = windowTitle
        self.bundleID = bundleID
        self.availableKeymaps = availableKeymaps
    }

    /// Formatted context string injected before the user's message.
    public var contextPrompt: String {
        var lines: [String] = ["[Gaming Context]"]

        if let platform = selectedPlatform {
            lines.append("Platform: \(platform)")
        } else {
            lines.append("Platform: none selected")
        }

        lines.append("Stream: \(streamStatus.rawValue)")

        if isNitroGenRunning {
            lines.append("NitroGen: RUNNING (fps=\(String(format: "%.1f", currentFPS)), steps=\(stepCount))")
        } else {
            lines.append("NitroGen: STOPPED")
        }

        if let title = windowTitle, !title.isEmpty {
            lines.append("Game window: \(title)")
        }
        if let bid = bundleID, !bid.isEmpty {
            lines.append("Bundle ID: \(bid)")
        }

        if !availableKeymaps.isEmpty {
            lines.append("Keymaps: \(availableKeymaps.joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Handler factory
// ═══════════════════════════════════════════════════════════════════

/// Creates an `AgentSendHandler` that enriches messages with gaming
/// context before sending to the agent backend.
///
/// The `contextProvider` closure is called on each send to capture
/// the latest gaming state snapshot.
public func makeGamingSendHandler(
    contextProvider: @escaping @Sendable @MainActor () -> GamingContext,
    baseSend: AgentSendHandler? = nil
) -> AgentSendHandler {
    return { text, shell in
        let ctx = contextProvider()
        let enriched = "\(ctx.contextPrompt)\n\n[User] \(text)"

        if let base = baseSend {
            // Route through the real agent backend with enriched context
            shell.input = ""
            await base(enriched, shell)
        } else {
            // Demo fallback — simulates an aware agent
            try? await Task.sleep(nanoseconds: 400_000_000)

            let response: String
            let lowered = text.lowercased()

            if lowered.contains("start") && (lowered.contains("play") || lowered.contains("nitrogen") || lowered.contains("agent")) {
                if ctx.selectedPlatform == nil {
                    response = "I see you haven't selected a gaming platform yet. Pick one — Xbox Cloud, GeForce NOW, Steam Link, or another — and I'll help you get started."
                } else if ctx.streamStatus != .playing && ctx.streamStatus != .paused {
                    response = "The \(ctx.selectedPlatform ?? "platform") stream isn't connected yet. Once you see the game running, tell me and I'll start NitroGen."
                } else if ctx.isNitroGenRunning {
                    response = "NitroGen is already running at \(String(format: "%.0f", ctx.currentFPS)) FPS with \(ctx.stepCount) steps played. Want me to stop and restart?"
                } else {
                    response = "Starting NitroGen agent! I'll capture the game window and begin autonomous gameplay. Say 'stop' anytime to take back control."
                }
            } else if lowered.contains("stop") {
                if ctx.isNitroGenRunning {
                    response = "Stopping NitroGen. The game is still running — you can play manually or ask me to start again."
                } else {
                    response = "NitroGen isn't running right now. Want me to start it?"
                }
            } else if lowered.contains("status") || lowered.contains("how") {
                if ctx.isNitroGenRunning {
                    response = "NitroGen is running on \(ctx.selectedPlatform ?? "the game") at \(String(format: "%.0f", ctx.currentFPS)) FPS. \(ctx.stepCount) steps played so far."
                } else {
                    response = "NitroGen is idle. Platform: \(ctx.selectedPlatform ?? "none"). Stream: \(ctx.streamStatus.rawValue)."
                }
            } else if lowered.contains("search") || lowered.contains("find") || lowered.contains("play ") {
                // Extract game name after "play" or "search for"
                let gameName = text
                    .replacingOccurrences(of: "search for ", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "find ", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "play ", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                response = "Searching for '\(gameName)' on \(ctx.selectedPlatform ?? "the platform")..."
            } else {
                response = "I'm your gaming agent. I can start/stop NitroGen, search for games, navigate platforms, and monitor gameplay. What would you like to do?"
            }

            shell.messages.append(.init(role: .agent, text: response))
        }
    }
}

/// Discover available keymap JSON files in the NitroGen keymaps directory.
public func discoverAvailableKeymaps() -> [String] {
    let keymapDir = Bundle.main.bundlePath + "/Contents/Resources/keymaps"
    let fallback = "/Users/home/swoosh/Sources/SwooshToolsets/NitroGen/keymaps"

    for dir in [keymapDir, fallback] {
        let url = URL(fileURLWithPath: dir)
        if let files = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
            return files
                .filter { $0.pathExtension == "json" }
                .map { $0.deletingPathExtension().lastPathComponent }
        }
    }
    return []
}

#endif
