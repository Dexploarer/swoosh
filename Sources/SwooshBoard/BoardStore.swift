// SwooshBoard/BoardStore.swift — 0.7A Board Store
//
// Persistence layer for boards, cards, comments, artifacts, blockers, events.
// In-memory for now. SQLite backing can replace this later.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Board store protocol
// ═══════════════════════════════════════════════════════════════════

public protocol BoardStoring: Sendable {
    func saveBoard(_ board: Board07A) async throws
    func getBoard(id: String) async throws -> Board07A?
    func listBoards() async throws -> [Board07A]

    func saveCard(_ card: BoardCard) async throws
    func updateCard(_ card: BoardCard) async throws
    func getCard(id: String) async throws -> BoardCard?
    func listCards(boardID: String, filter: BoardCardFilter?) async throws -> [BoardCard]
    func deleteCard(id: String) async throws

    func saveComment(_ comment: BoardComment) async throws
    func listComments(cardID: String) async throws -> [BoardComment]

    func saveArtifact(_ artifact: BoardArtifact) async throws
    func listArtifacts(cardID: String) async throws -> [BoardArtifact]

    func saveBlocker(_ blocker: BoardBlocker) async throws
    func updateBlocker(_ blocker: BoardBlocker) async throws
    func listBlockers(cardID: String) async throws -> [BoardBlocker]

    func saveEvent(_ event: BoardEvent) async throws
    func listEvents(cardID: String?, boardID: String?, limit: Int?) async throws -> [BoardEvent]
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - In-memory board store
// ═══════════════════════════════════════════════════════════════════

public actor InMemoryBoardStore: BoardStoring {
    private var boards: [String: Board07A] = [:]
    private var cards: [String: BoardCard] = [:]
    private var comments: [String: BoardComment] = [:]
    private var artifacts: [String: BoardArtifact] = [:]
    private var blockers: [String: BoardBlocker] = [:]
    private var events: [String: BoardEvent] = [:]

    public init() {}

    // Board
    public func saveBoard(_ board: Board07A) { boards[board.id] = board }
    public func getBoard(id: String) -> Board07A? { boards[id] }
    public func listBoards() -> [Board07A] {
        Array(boards.values).sorted { $0.createdAt > $1.createdAt }
    }

    // Card
    public func saveCard(_ card: BoardCard) { cards[card.id] = card }
    public func updateCard(_ card: BoardCard) { cards[card.id] = card }
    public func getCard(id: String) -> BoardCard? { cards[id] }
    public func deleteCard(id: String) { cards.removeValue(forKey: id) }
    public func listCards(boardID: String, filter: BoardCardFilter?) -> [BoardCard] {
        var result = cards.values.filter { $0.boardID == boardID }
        if let f = filter {
            if let s = f.status { result = result.filter { $0.status == s } }
            if let k = f.kind { result = result.filter { $0.kind == k } }
            if let p = f.priority { result = result.filter { $0.priority == p } }
            if let a = f.assigneeID { result = result.filter { $0.assignee?.id == a } }
            if let sk = f.sourceKind { result = result.filter { $0.source.kind == sk } }
            if let q = f.search {
                let lq = q.lowercased()
                result = result.filter { $0.title.lowercased().contains(lq) || ($0.summary?.lowercased().contains(lq) ?? false) }
            }
        }
        return result.sorted { $0.updatedAt > $1.updatedAt }
    }

    // Comment
    public func saveComment(_ c: BoardComment) { comments[c.id] = c }
    public func listComments(cardID: String) -> [BoardComment] {
        comments.values.filter { $0.cardID == cardID }.sorted { $0.createdAt > $1.createdAt }
    }

    // Artifact
    public func saveArtifact(_ a: BoardArtifact) { artifacts[a.id] = a }
    public func listArtifacts(cardID: String) -> [BoardArtifact] {
        artifacts.values.filter { $0.cardID == cardID }.sorted { $0.createdAt > $1.createdAt }
    }

    // Blocker
    public func saveBlocker(_ b: BoardBlocker) { blockers[b.id] = b }
    public func updateBlocker(_ b: BoardBlocker) { blockers[b.id] = b }
    public func listBlockers(cardID: String) -> [BoardBlocker] {
        blockers.values.filter { $0.cardID == cardID }.sorted { $0.createdAt > $1.createdAt }
    }

    // Event
    public func saveEvent(_ e: BoardEvent) { events[e.id] = e }
    public func listEvents(cardID: String?, boardID: String?, limit: Int?) -> [BoardEvent] {
        var result = Array(events.values)
        if let c = cardID { result = result.filter { $0.cardID == c } }
        if let b = boardID { result = result.filter { $0.boardID == b } }
        result.sort { $0.createdAt > $1.createdAt }
        if let l = limit { result = Array(result.prefix(l)) }
        return result
    }
}
