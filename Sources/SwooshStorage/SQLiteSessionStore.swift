// SwooshStorage/SQLiteSessionStore.swift — Durable session store — 0.9S
//
// Persists chat session transcripts to SQLite. Replaces InMemorySessionStore.

import Foundation
import SQLite
import SwooshCore

public actor SQLiteSessionStore: SwooshCore.SessionStoring {
    private let db: SwooshDatabase

    public init(db: SwooshDatabase) {
        self.db = db
    }

    public func appendMessage(sessionID: String, message: SwooshCore.ChatMessage) async throws {
        let now = swooshDateString(message.createdAt)
        try await db.execute { conn -> Void in
            _ = try conn.run("""
                INSERT INTO sessions (session_id, role, content, tool_calls, created_at)
                VALUES (?, ?, ?, ?, ?)
            """, sessionID, message.role.rawValue, message.content, nil as String?, now)
        }
    }

    public func loadTranscript(sessionID: String) async throws -> [SwooshCore.ChatMessage] {
        try await db.execute { conn in
            let stmt = try conn.prepare("""
                SELECT role, content, created_at FROM sessions
                WHERE session_id = ? ORDER BY id ASC
            """, sessionID)
            var messages: [SwooshCore.ChatMessage] = []
            for row in stmt {
                let role = SwooshCore.ChatRole(rawValue: row[0] as! String) ?? .user
                messages.append(SwooshCore.ChatMessage(
                    role: role,
                    content: row[1] as! String,
                    createdAt: swooshParseDate(row[2] as! String)
                ))
            }
            return messages
        }
    }
}
