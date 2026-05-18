// SwooshActantBackend/ActantResponseAuditor.swift — ResponseAuditing backed by ActantDB
//
// Each AgentKernel response writes one structured `append_agent_message` event
// with a JSON sentinel in the text field. This puts the audit record on the
// same hash-chained ledger Studio + replay already consume — no separate
// audit storage, no separate query.
//
// Event payload format (JSON inside the message text):
//   {
//     "_swoosh_audit": true,
//     "session_id":             "<session>",
//     "response_id":            "<uuid>",
//     "model_used":             "...",
//     "memory_ids_used":        ["mem_1", "mem_2"],
//     "setup_report_used":      true,
//     "permission_summary_used": true,
//     "rejected_memories_excluded": true,
//     "raw_scout_records_excluded": true,
//     "cookies_excluded":       true,
//     "secrets_excluded":       true,
//     "created_at":             "2026-05-18T12:00:00Z"
//   }

import Foundation
import ActantDB
import SwooshCore

public final class ActantResponseAuditor: ResponseAuditing, Sendable {
    private let config: ActantBackendConfig
    public init(_ config: ActantBackendConfig) {
        self.config = config
    }

    public func logResponseAudit(_ audit: ResponseAuditRecord) async throws {
        let payload = encode(audit)
        _ = try await config.client.appendAgentMessage(
            workspaceID: config.workspaceID,
            actorID: config.actorID,
            sessionID: audit.sessionID,
            text: payload
        )
    }

    public func lastResponseAudit(sessionID: String) async throws -> ResponseAuditRecord? {
        let events = try await config.client.events(sessionID: sessionID)
        // Walk newest-first looking for an agent_message_appended whose
        // payload contains our sentinel.
        for event in events.reversed() where event.eventType == "agent_message_appended" {
            guard let payload = try? event.parsedPayload(),
                  let text = payload["text"]?.stringValue,
                  let data = text.data(using: .utf8) else { continue }
            if let decoded = try? JSONDecoder().decode(WireAudit.self, from: data),
               decoded._swoosh_audit == true {
                return decoded.toRecord()
            }
        }
        return nil
    }

    // MARK: - Wire shape

    private func encode(_ audit: ResponseAuditRecord) -> String {
        let wire = WireAudit(
            _swoosh_audit: true,
            session_id: audit.sessionID,
            response_id: audit.responseID,
            model_used: audit.modelUsed,
            memory_ids_used: audit.memoryIDsUsed,
            setup_report_used: audit.setupReportUsed,
            permission_summary_used: audit.permissionSummaryUsed,
            rejected_memories_excluded: audit.rejectedMemoriesExcluded,
            raw_scout_records_excluded: audit.rawScoutRecordsExcluded,
            cookies_excluded: audit.cookiesExcluded,
            secrets_excluded: audit.secretsExcluded,
            created_at: ISO8601DateFormatter().string(from: audit.createdAt)
        )
        guard let data = try? JSONEncoder().encode(wire),
              let s = String(data: data, encoding: .utf8) else {
            return "{\"_swoosh_audit\":true}"
        }
        return s
    }

    private struct WireAudit: Codable, Sendable {
        let _swoosh_audit: Bool
        let session_id: String
        let response_id: String
        let model_used: String
        let memory_ids_used: [String]
        let setup_report_used: Bool
        let permission_summary_used: Bool
        let rejected_memories_excluded: Bool
        let raw_scout_records_excluded: Bool
        let cookies_excluded: Bool
        let secrets_excluded: Bool
        let created_at: String

        func toRecord() -> ResponseAuditRecord {
            let date = ISO8601DateFormatter().date(from: created_at) ?? Date()
            return ResponseAuditRecord(
                sessionID: session_id,
                responseID: response_id,
                modelUsed: model_used,
                memoryIDsUsed: memory_ids_used,
                setupReportUsed: setup_report_used,
                permissionSummaryUsed: permission_summary_used,
                rejectedMemoriesExcluded: rejected_memories_excluded,
                rawScoutRecordsExcluded: raw_scout_records_excluded,
                cookiesExcluded: cookies_excluded,
                secretsExcluded: secrets_excluded,
                createdAt: date
            )
        }
    }
}
