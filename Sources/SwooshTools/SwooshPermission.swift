// SwooshTools/SwooshPermission.swift — Typed Permission Model
//
// Every permission in Swoosh is typed. No loose strings.
// The permission set covers: system, tools, files, dev, web, Apple native,
// workflow, EVM, and Solana domains.

import Foundation

// MARK: - Permission

public enum SwooshPermission: String, Codable, Sendable, CaseIterable, Hashable {

    // ── Existing (system / device) ────────────────────────────────
    case deviceProfileRead
    case installedAppsRead
    case runningAppsRead
    case selectedFolderRead
    case selectedFolderWrite
    case calendarRead
    case remindersRead
    case contactsRead
    case browserTabsRead
    case browserHistoryRead
    case appleEvents
    case screenCapture
    case shellRead
    case shellRun
    case memoryRead
    case memoryWrite
    case networkAccess

    // ── Self-improvement pillars (skills / goals / manifesting) ────
    case skillsRead
    case skillsWrite
    case goalsRead
    case goalsWrite
    case manifestRead
    case manifestRun

    // ── Detour Calendar (agent-managed; NOT Apple Calendar/EventKit) ─
    // Gate the agent's own calendar tools. Distinct from `calendarRead`/
    // `calendarWrite` above, which gate the *system* (Apple/Scout) calendar.
    case detourCalendarRead
    case detourCalendarWrite

    // ── Personal-data Scout sources ────────────────────────────────
    // These power Scout's deep personalization layer. Every one of
    // them grants raw access to *very* personal data; the trust
    // contract is that records never enter prompts directly — only
    // user-approved memory candidates derived from them do.
    case focusModeRead
    case appUsageRead          // macOS NSWorkspace frontmost-app history
    case screenTimeRead        // iOS DeviceActivity / FamilyControls
    case healthSleepRead
    case healthActivityRead
    case musicLibraryRead
    case photosRead
    case recentDocumentsRead

    // ── Tool / runtime ────────────────────────────────────────────
    case toolRead
    case toolWrite
    case approvalResolve
    case auditRead
    case auditWrite

    // ── Files / dev ───────────────────────────────────────────────
    case fileRead
    case fileWrite
    case gitRead
    case gitWrite
    case swiftBuild
    case xcodeBuild

    // ── Web / browser ─────────────────────────────────────────────
    case webSearch
    case webExtract
    case browserRead
    case browserControl

    // ── Apple native ──────────────────────────────────────────────
    case calendarWrite
    case remindersWrite
    case notesRead
    case notesWrite
    case shortcutsRun
    case finderRead
    case finderWrite

    // ── Workflow ──────────────────────────────────────────────────
    case workflowRead
    case workflowWrite
    case workflowRun
    case scheduleRead
    case scheduleWrite
    case scheduleRun

    // ── EVM ───────────────────────────────────────────────────────
    case evmRead
    case evmBuildTransaction
    case evmRequestSignature
    case evmBroadcast
    case evmMainnetWrite

    // ── Solana ────────────────────────────────────────────────────
    case solanaRead
    case solanaBuildTransaction
    case solanaRequestSignature
    case solanaBroadcast
    case solanaMainnetWrite

    // ── Hyperliquid ───────────────────────────────────────────────
    case networkRead              // generic authenticated read (no key)
    case hyperliquidTrade         // place/cancel orders, update leverage
    case hyperliquidTransfer      // USD/spot transfers, bridge withdraw (high-risk)

    // ── MCP ───────────────────────────────────────────────────────
    // Agent-facing MCP access. Trust mutations (add/enable/disable/remove
    // server) stay CLI-only — they are never wired as agent tools.
    case mcpRead                  // list configured servers + their discovered tools
    case mcpExecute               // call a discovered MCP tool (untrusted by default; high-risk gated)

    // ── Media generation ──────────────────────────────────────────
    // Generative-media privileges. Distinct from tool/file writes so a
    // user can grant chat-with-images without granting shell access.
    // Cloud-backed providers also need `networkAccess`; the local image
    // path (Apple Image Playground) needs only `imageGenerate`.
    case imageGenerate            // Text-to-image (local or cloud)
    case videoGenerate            // Text-to-video (cloud only today)
    case threeDGenerate           // Text/image-to-3D (cloud only today)
    case musicGenerate            // Text-to-music (cloud only today)

    // ── Plugins ───────────────────────────────────────────────────
    // Plugin host admin permissions. These gate *plugin lifecycle* —
    // install / uninstall / enable / disable — and are humanOnly: the
    // model can never enable a plugin, only request that the user does.
    // Plugin tools themselves declare ordinary SwooshPermission cases
    // (fileRead, networkAccess, etc.) which the user grants when they
    // approve the plugin at enable time. There is no `pluginExecute`
    // permission — each plugin tool routes through the existing
    // firewall on its own declared permission, like every other tool.
    case pluginInstall
    case pluginUninstall
    case pluginEnable
    case pluginDisable

    // ── NitroGen gaming agent ─────────────────────────────────────
    case nitrogenControl          // start/stop the NitroGen inference server + player
    case nitrogenRead             // status checks, screenshot grabs
}

// MARK: - Permission state

public enum PermissionState: String, Codable, Sendable {
    case granted
    case denied
    case pending
    case notRequested
}
