// SwooshStorage/SQLiteMemoryStore.swift — Durable memory store — 0.9S

import Foundation
import SQLite
import SwooshTools

public actor SQLiteMemoryStore: MemoryToolStoring {
    private let db: SwooshDatabase

    public init(db: SwooshDatabase) {
        self.db = db
    }

    // MARK: - Approved memories

    public func listApproved(category: MemoryCategory?, limit: Int?) async throws -> [ApprovedMemory] {
        try await db.execute { conn in
            let stmt: Statement
            if let cat = category {
                stmt = try conn.prepare("""
                    SELECT id, text, category, sensitivity, confidence, created_at, last_used_at
                    FROM approved_memories WHERE category = ?
                    ORDER BY created_at DESC \(limit.map { "LIMIT \($0)" } ?? "")
                """, cat.rawValue)
            } else {
                stmt = try conn.prepare("""
                    SELECT id, text, category, sensitivity, confidence, created_at, last_used_at
                    FROM approved_memories
                    ORDER BY created_at DESC \(limit.map { "LIMIT \($0)" } ?? "")
                """)
            }
            return Self.parseApproved(from: stmt)
        }
    }

    public func searchApproved(query: String, category: MemoryCategory?, limit: Int?) async throws -> [ApprovedMemorySearchResult] {
        try await db.execute { conn in
            let pattern = "%\(query)%"
            var sql = """
                SELECT id, text, category, sensitivity, confidence, created_at, last_used_at
                FROM approved_memories WHERE text LIKE ?
            """
            var bindings: [Binding?] = [pattern]
            if let cat = category {
                sql += " AND category = ?"
                bindings.append(cat.rawValue)
            }
            sql += " ORDER BY created_at DESC"
            if let lim = limit { sql += " LIMIT \(lim)" }

            let stmt = try conn.prepare(sql, bindings)
            let memories = Self.parseApproved(from: stmt)
            return memories.map { memory in
                let needle = query.lowercased()
                let haystack = memory.text.lowercased()
                let score = haystack == needle ? 1.0
                    : max(0.2, Double(needle.count) / Double(max(haystack.count, 1)))
                return ApprovedMemorySearchResult(memory: memory, score: score, reason: "text match")
            }
        }
    }

    public func getApproved(id: String) async throws -> ApprovedMemory? {
        try await db.execute { conn -> ApprovedMemory? in
            let stmt = try conn.prepare("""
                SELECT id, text, category, sensitivity, confidence, created_at, last_used_at
                FROM approved_memories WHERE id = ?
            """, id)
            return Self.parseApproved(from: stmt).first
        }
    }

    // MARK: - Candidates

    public func listCandidates(status: CandidateStatus?, limit: Int?) async throws -> [MemoryCandidate] {
        try await db.execute { conn in
            let stmt: Statement
            if let s = status {
                stmt = try conn.prepare("""
                    SELECT id, text, category, sensitivity, confidence, evidence, status, created_at
                    FROM memory_candidates WHERE status = ?
                    ORDER BY created_at DESC \(limit.map { "LIMIT \($0)" } ?? "")
                """, s.rawValue)
            } else {
                stmt = try conn.prepare("""
                    SELECT id, text, category, sensitivity, confidence, evidence, status, created_at
                    FROM memory_candidates
                    ORDER BY created_at DESC \(limit.map { "LIMIT \($0)" } ?? "")
                """)
            }
            return Self.parseCandidates(from: stmt)
        }
    }

    public func getCandidate(id: String) async throws -> MemoryCandidate? {
        try await db.execute { conn -> MemoryCandidate? in
            let stmt = try conn.prepare("""
                SELECT id, text, category, sensitivity, confidence, evidence, status, created_at
                FROM memory_candidates WHERE id = ?
            """, id)
            return Self.parseCandidates(from: stmt).first
        }
    }

    public func propose(_ input: ProposeMemoryCandidateInput) async throws -> String {
        let id = UUID().uuidString
        let evidenceJSON = String(
            data: (try? JSONEncoder().encode(input.evidence)) ?? Data("[]".utf8),
            encoding: .utf8
        ) ?? "[]"
        let now = swooshDateString()
        try await db.execute { conn -> Void in
            _ = try conn.run("""
                INSERT INTO memory_candidates
                    (id, text, category, sensitivity, confidence, evidence, status, created_at)
                VALUES (?, ?, ?, ?, ?, ?, 'pending', ?)
            """, id, input.text, input.category.rawValue, input.sensitivity.rawValue,
                input.confidence, evidenceJSON, now)
        }
        return id
    }

    public func approve(candidateID: String, finalText: String?) async throws -> String {
        let memoryID = UUID().uuidString
        let now = swooshDateString()
        try await db.execute { conn -> Void in
            let stmt = try conn.prepare("""
                SELECT text, category, sensitivity, confidence
                FROM memory_candidates WHERE id = ?
            """, candidateID)
            var found = false
            var text = ""; var category = ""; var sensitivity = ""; var confidence = 0.0
            for row in stmt {
                text = finalText ?? (row[0] as! String)
                category = row[1] as! String
                sensitivity = row[2] as! String
                confidence = swooshDouble(row[3])
                found = true
                break
            }
            guard found else { throw ToolError.notFound(candidateID) }
            _ = try conn.run("""
                INSERT INTO approved_memories
                    (id, text, category, sensitivity, confidence, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
            """, memoryID, text, category, sensitivity, confidence, now)
            _ = try conn.run(
                "UPDATE memory_candidates SET status = 'approved' WHERE id = ?", candidateID)
        }
        return memoryID
    }

    public func reject(candidateID: String, reason: String?) async throws {
        try await db.execute { conn -> Void in
            _ = try conn.run(
                "UPDATE memory_candidates SET status = 'rejected' WHERE id = ?", candidateID)
            if conn.changes == 0 { throw ToolError.notFound(candidateID) }
        }
    }

    public func edit(candidateID: String, newText: String, newCategory: MemoryCategory?, newSensitivity: Sensitivity?) async throws {
        try await db.execute { conn -> Void in
            var updates = ["text = ?", "status = 'edited'"]
            var bindings: [Binding?] = [newText]
            if let cat = newCategory { updates.append("category = ?"); bindings.append(cat.rawValue) }
            if let sens = newSensitivity { updates.append("sensitivity = ?"); bindings.append(sens.rawValue) }
            bindings.append(candidateID)
            _ = try conn.run(
                "UPDATE memory_candidates SET \(updates.joined(separator: ", ")) WHERE id = ?",
                bindings)
            if conn.changes == 0 { throw ToolError.notFound(candidateID) }
        }
    }

    // MARK: - Parse helpers (called inside closure — Statement never crosses actor boundary)

    private static func parseApproved(from stmt: Statement) -> [ApprovedMemory] {
        var results: [ApprovedMemory] = []
        for row in stmt {
            guard let category = MemoryCategory(rawValue: row[2] as! String) else { continue }
            results.append(ApprovedMemory(
                id: row[0] as! String, text: row[1] as! String, category: category,
                sensitivity: Sensitivity(rawValue: row[3] as! String) ?? .normal,
                confidence: swooshDouble(row[4]),
                createdAt: swooshParseDate(row[5] as! String),
                lastUsedAt: (row[6] as? String).map(swooshParseDate)
            ))
        }
        return results
    }

    private static func parseCandidates(from stmt: Statement) -> [MemoryCandidate] {
        var results: [MemoryCandidate] = []
        for row in stmt {
            guard let category = MemoryCategory(rawValue: row[2] as! String),
                  let status = CandidateStatus(rawValue: row[6] as! String) else { continue }
            let evidenceJSON = row[5] as? String ?? "[]"
            let evidence = (try? JSONDecoder().decode(
                [EvidencePointer].self, from: Data(evidenceJSON.utf8)
            )) ?? []
            results.append(MemoryCandidate(
                id: row[0] as! String, text: row[1] as! String, category: category,
                sensitivity: Sensitivity(rawValue: row[3] as! String) ?? .normal,
                confidence: swooshDouble(row[4]), evidence: evidence, status: status,
                createdAt: swooshParseDate(row[7] as! String)
            ))
        }
        return results
    }
}
