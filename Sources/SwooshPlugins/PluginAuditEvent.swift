// SwooshPlugins/PluginAuditEvent.swift — Audit event type for the plugin lifecycle — 0.9A
//
// Every state transition + tool call on a plugin produces a
// `PluginAuditEvent`. `PluginRegistry` keeps an in-memory ring for
// callers that don't wire ActantDB; `PluginHost` forwards events to the
// daemon's `AuditLogging` impl so they land on the same ledger as model
// turns and tool calls.

import Foundation

public struct PluginAuditEvent: Codable, Sendable {
    public let kind: PluginAuditEventKind
    public let pluginID: String
    public let message: String
    public let createdAt: Date

    public init(
        kind: PluginAuditEventKind, pluginID: String, message: String, createdAt: Date = Date()
    ) {
        self.kind = kind
        self.pluginID = pluginID
        self.message = message
        self.createdAt = createdAt
    }
}

public enum PluginAuditEventKind: String, Codable, Sendable {
    case discovered, inspected, enableRequested, enabled, disabled
    case toolRegistered, toolCallStarted, toolCallCompleted, toolCallFailed
    case sandboxViolation
}
