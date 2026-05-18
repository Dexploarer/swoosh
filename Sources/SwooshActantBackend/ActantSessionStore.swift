// SwooshActantBackend/ActantSessionStore.swift — SessionStoring backed by ActantDB
//
// appendMessage(.user)      → dispatch(.appendUserMessage)
// appendMessage(.assistant) → dispatch(.appendAgentMessage)
// appendMessage(.system)    → no-op; PromptBuilder regenerates the system prompt every
//                             call, so persisting it would just duplicate data
// appendMessage(.tool)      → dispatch(.appendAgentMessage) with role marker in text;
//                             tool result events also exist on the ledger but the
//                             kernel's transcript wants a flat ChatMessage stream
//
// loadTranscript → events(sessionID:) + decode payload_inline back to ChatMessage[].
//   Filters for `user_message_received` / `agent_message_appended` event types.
//   Other event types (tool calls, approvals) live on the same ledger but are
//   surfaced via separate query paths (Studio, /v1/approvals).

import Foundation
import ActantDB
import SwooshCore

public final class ActantSessionStore: SessionStoring, Sendable {
    private let config: ActantBackendConfig

    public init(_ config: ActantBackendConfig) {
        self.config = config
    }

    public func appendMessage(sessionID: String, message: ChatMessage) async throws {
        switch message.role {
        case .system:
            return  // PromptBuilder owns system prompts; the ledger doesn't need them
        case .user:
            _ = try await config.client.appendUserMessage(
                workspaceID: config.workspaceID,
                actorID: config.actorID,
                sessionID: sessionID,
                text: message.content
            )
        case .assistant:
            _ = try await config.client.appendAgentMessage(
                workspaceID: config.workspaceID,
                actorID: config.actorID,
                sessionID: sessionID,
                text: message.content
            )
        case .tool:
            // Tool messages are surfaced on the ledger via record_tool_result; if a
            // caller is also adding one to the transcript, persist it as an agent
            // message prefixed with `[tool] ` so loadTranscript round-trips it back.
            _ = try await config.client.appendAgentMessage(
                workspaceID: config.workspaceID,
                actorID: config.actorID,
                sessionID: sessionID,
                text: "[tool] \(message.content)"
            )
        }
    }

    public func loadTranscript(sessionID: String) async throws -> [ChatMessage] {
        let events = try await config.client.events(sessionID: sessionID)
        var messages: [ChatMessage] = []
        messages.reserveCapacity(events.count)
        for event in events {
            switch event.eventType {
            case "user_message_received":
                if let text = try messageText(from: event) {
                    messages.append(ChatMessage(role: .user, content: text, createdAt: parseDate(event.createdAt)))
                }
            case "agent_message_appended":
                if let text = try messageText(from: event) {
                    if text.hasPrefix("[tool] ") {
                        messages.append(ChatMessage(
                            role: .tool,
                            content: String(text.dropFirst("[tool] ".count)),
                            createdAt: parseDate(event.createdAt)
                        ))
                    } else {
                        messages.append(ChatMessage(role: .assistant, content: text, createdAt: parseDate(event.createdAt)))
                    }
                }
            default:
                continue
            }
        }
        return messages
    }

    // MARK: - Helpers

    private func messageText(from event: AgentEvent) throws -> String? {
        guard let payload = try event.parsedPayload() else { return nil }
        return payload["text"]?.stringValue
    }

    private func parseDate(_ rfc3339: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: rfc3339) ?? ISO8601DateFormatter().date(from: rfc3339) ?? Date()
    }
}
