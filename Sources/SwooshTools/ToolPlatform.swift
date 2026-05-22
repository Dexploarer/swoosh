// SwooshTools/ToolPlatform.swift — Platform constraints on tools
//
// Some tools only make sense on the Mac host (file system, git, shell,
// large local models). Others are safe to register on iOS too (read-only
// memory queries, audit reads, remote RPCs). Tagging this explicitly lets
// the registrar drop incompatible tools at registration time so the
// model's catalog reflects what is actually runnable.
//
// Granularity is at the toolset level by default; an individual tool can
// override `platforms` if it disagrees with its toolset.

import Foundation

/// A platform on which Swoosh code can run. Used as a tool-registration
/// filter — *not* a permission. Tools missing from this set are never
/// added to the registry on the corresponding platform.
public enum ToolPlatform: String, Codable, Sendable, CaseIterable, Hashable {
    case macOS
    case iOS
    case linux

    /// The platform of the currently-running process.
    public static var current: ToolPlatform {
        #if os(macOS)
        return .macOS
        #elseif os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        return .iOS
        #elseif os(Linux)
        return .linux
        #else
        return .macOS
        #endif
    }
}

extension ToolsetID {
    /// Default platform set for tools in this toolset. Overridable per tool
    /// via `SwooshTool.platforms`.
    public var defaultPlatforms: Set<ToolPlatform> {
        switch self {
        // Filesystem / dev shell / host-process toolsets are Mac-only — they
        // assume an unrestricted home directory and the ability to spawn
        // processes. They have no meaning in an iOS sandbox.
        case .files, .git, .swiftDev, .xcode, .terminal:
            return [.macOS]
        // Browser-host integrations target macOS automation surfaces today.
        case .browser, .apple:
            return [.macOS]
        // Everything else — agent core, memory, permissions, scout, audit,
        // workflow, blockchain RPCs, MCP, web, plus the new self-
        // improvement pillars (skills / goals / manifesting) — runs
        // anywhere the kernel is hosted. The manifester itself is Mac-
        // side today, but its tool surface (read history, run-once on
        // user request) is fine to expose on iOS.
        case .core, .memory, .permissions, .scout, .audit, .workflow, .cron,
             .web, .evm, .solana, .launchpads, .hyperliquid, .uniswap, .mcp,
             .skills, .goals, .manifesting:
            return [.macOS, .iOS, .linux]
        // The plugin host loads dynamic code (Swift entrypoints, executables,
        // wasm) — server-side only. The iOS app talks to plugins through the
        // daemon's HTTP API, never directly.
        case .plugins:
            return [.macOS, .linux]
        }
    }
}
