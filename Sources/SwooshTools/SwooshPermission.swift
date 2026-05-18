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
    case memoryWrite
    case networkAccess

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
}

// MARK: - Permission state

public enum PermissionState: String, Codable, Sendable {
    case granted
    case denied
    case pending
    case notRequested
}
