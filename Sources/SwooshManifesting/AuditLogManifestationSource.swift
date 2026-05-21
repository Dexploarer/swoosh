// SwooshManifesting/AuditLogManifestationSource.swift — Real audit source — 0.9P
//
// `Manifester` defaults to `EmptyManifestationAuditSource`, which yields
// no events — so every scheduled pass short-circuits to `.skipped` and
// the self-improvement loop mines nothing. This source projects the
// agent's durable tool-audit log into the event shape the mining phase
// reasons about, so manifestation passes see real activity.

import Foundation
import SwooshTools

/// `ManifestationAuditSource` backed by the agent's tool-audit log
/// (`AuditLogging`). Each `AuditEntry` is projected into the
/// redaction-safe `ManifestationAuditEvent` shape and filtered to the
/// window since the last completed manifestation.
public struct AuditLogManifestationSource: ManifestationAuditSource {
    private let audit: any AuditLogging
    private let maxEvents: Int

    /// - Parameters:
    ///   - audit: the durable tool-audit log to mine.
    ///   - maxEvents: ceiling on how many recent entries one pass reads.
    public init(audit: any AuditLogging, maxEvents: Int = 2000) {
        self.audit = audit
        self.maxEvents = maxEvents
    }

    public func eventsSince(_ cursor: Date?) async throws -> [ManifestationAuditEvent] {
        let entries = await audit.tail(limit: maxEvents)
        return entries
            .filter { cursor == nil || $0.timestamp > cursor! }
            .map { entry in
                ManifestationAuditEvent(
                    id: entry.id,
                    kind: entry.kind.rawValue,
                    sessionID: entry.sessionID,
                    toolName: entry.toolName,
                    summary: entry.detail,
                    timestamp: entry.timestamp
                )
            }
            .sorted { $0.timestamp < $1.timestamp }
    }
}
