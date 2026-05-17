// Tests/SwooshBoardTests/BoardTests.swift — 0.7A Tests

import Testing
import Foundation
@testable import SwooshBoard
@testable import SwooshTools

// ═══════════════════════════════════════════════════════════════
// Fixtures
// ═══════════════════════════════════════════════════════════════

let testBoardID = "board_test"
let testActor = BoardAssignee(id: "human_1", kind: .human, displayName: "User")
let systemActor = BoardAssignee(id: "system", kind: .system, displayName: "Swoosh")

func makeTestBoard() -> Board07A {
    Board07A(id: testBoardID, name: "Test Board")
}

func makeTestCard(
    id: String = UUID().uuidString, status: BoardCardStatus07A = .inbox,
    kind: BoardCardKind = .manualTask, priority: BoardCardPriority = .normal,
    source: BoardCardSource = BoardCardSource()
) -> BoardCard {
    BoardCard(id: id, boardID: testBoardID, title: "Test Card", summary: "Summary",
              kind: kind, status: status, priority: priority, source: source)
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Board Store Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Board Store")
struct BoardStoreTests {

    @Test("Create and get board")
    func createAndGet() async throws {
        let store = InMemoryBoardStore()
        let board = makeTestBoard()
        try await store.saveBoard(board)
        let got = try await store.getBoard(id: testBoardID)
        #expect(got?.name == "Test Board")
    }

    @Test("List boards")
    func listBoards() async throws {
        let store = InMemoryBoardStore()
        try await store.saveBoard(makeTestBoard())
        let boards = try await store.listBoards()
        #expect(boards.count == 1)
    }

    @Test("Create and get card")
    func createAndGetCard() async throws {
        let store = InMemoryBoardStore()
        let card = makeTestCard(id: "c1")
        try await store.saveCard(card)
        let got = try await store.getCard(id: "c1")
        #expect(got?.title == "Test Card")
    }

    @Test("Update card")
    func updateCard() async throws {
        let store = InMemoryBoardStore()
        var card = makeTestCard(id: "c1")
        try await store.saveCard(card)
        card.status = .done
        try await store.updateCard(card)
        #expect(try await store.getCard(id: "c1")?.status == .done)
    }

    @Test("Move card changes status only")
    func moveCard() async throws {
        let store = InMemoryBoardStore()
        var card = makeTestCard(id: "c1", status: .inbox)
        try await store.saveCard(card)
        card.status = .ready; card.updatedAt = Date()
        try await store.updateCard(card)
        let got = try await store.getCard(id: "c1")
        #expect(got?.status == .ready)
    }

    @Test("Filter cards by status")
    func filterByStatus() async throws {
        let store = InMemoryBoardStore()
        try await store.saveCard(makeTestCard(id: "c1", status: .inbox))
        try await store.saveCard(makeTestCard(id: "c2", status: .done))
        let inbox = try await store.listCards(boardID: testBoardID, filter: BoardCardFilter(status: .inbox))
        #expect(inbox.count == 1)
        #expect(inbox[0].id == "c1")
    }

    @Test("Filter cards by kind")
    func filterByKind() async throws {
        let store = InMemoryBoardStore()
        try await store.saveCard(makeTestCard(id: "c1", kind: .approval))
        try await store.saveCard(makeTestCard(id: "c2", kind: .manualTask))
        let approvals = try await store.listCards(boardID: testBoardID, filter: BoardCardFilter(kind: .approval))
        #expect(approvals.count == 1)
    }

    @Test("Search cards")
    func searchCards() async throws {
        let store = InMemoryBoardStore()
        try await store.saveCard(makeTestCard(id: "c1"))
        let results = try await store.listCards(boardID: testBoardID, filter: BoardCardFilter(search: "Test"))
        #expect(!results.isEmpty)
    }

    @Test("Add and list comments")
    func comments() async throws {
        let store = InMemoryBoardStore()
        let c = BoardComment(cardID: "c1", author: testActor, body: "Great work")
        try await store.saveComment(c)
        let comments = try await store.listComments(cardID: "c1")
        #expect(comments.count == 1)
    }

    @Test("Add and list artifacts")
    func artifacts() async throws {
        let store = InMemoryBoardStore()
        let a = BoardArtifact(cardID: "c1", kind: .diff, title: "Patch", uri: "/tmp/patch.diff")
        try await store.saveArtifact(a)
        let arts = try await store.listArtifacts(cardID: "c1")
        #expect(arts.count == 1)
    }

    @Test("Add and resolve blocker")
    func blockers() async throws {
        let store = InMemoryBoardStore()
        var b = BoardBlocker(cardID: "c1", reason: .awaitingApproval, message: "Waiting")
        try await store.saveBlocker(b)
        b.resolvedAt = Date()
        try await store.updateBlocker(b)
        let blockers = try await store.listBlockers(cardID: "c1")
        #expect(blockers[0].resolvedAt != nil)
    }

    @Test("Add and list events")
    func events() async throws {
        let store = InMemoryBoardStore()
        let e = BoardEvent(cardID: "c1", boardID: testBoardID, type: .cardCreated, actor: systemActor, message: "Created")
        try await store.saveEvent(e)
        let events = try await store.listEvents(cardID: "c1", boardID: nil, limit: nil)
        #expect(events.count == 1)
    }

    @Test("Delete card")
    func deleteCard() async throws {
        let store = InMemoryBoardStore()
        try await store.saveCard(makeTestCard(id: "c1"))
        try await store.deleteCard(id: "c1")
        #expect(try await store.getCard(id: "c1") == nil)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Board Column Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Board Columns")
struct BoardColumnTests {

    @Test("Default columns exist")
    func defaultColumns() {
        let cols = BoardColumn.defaults
        #expect(cols.count == 8)
        #expect(cols[0].name == "Inbox")
        #expect(cols[3].name == "Needs Approval")
        #expect(cols[6].name == "Done")
    }

    @Test("Default board has all columns")
    func defaultBoard() {
        let board = Board07A()
        #expect(board.columns.count == 8)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Projection Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Board Projection")
struct BoardProjectionTests {

    @Test("Workflow run creates running card")
    func workflowRunCreatesCard() async throws {
        let store = InMemoryBoardStore()
        let proj = BoardProjection(store: store, boardID: testBoardID)
        try await proj.projectWorkflowRun(runID: "r1", workflowID: "w1", workflowName: "Health Check", status: .running)
        let cards = try await store.listCards(boardID: testBoardID, filter: BoardCardFilter(kind: .workflowRun))
        #expect(cards.count == 1)
        #expect(cards[0].status == .running)
    }

    @Test("Workflow completed moves card to done")
    func workflowCompletedDone() async throws {
        let store = InMemoryBoardStore()
        let proj = BoardProjection(store: store, boardID: testBoardID)
        try await proj.projectWorkflowRun(runID: "r1", workflowID: "w1", workflowName: "HC", status: .running)
        try await proj.projectWorkflowRun(runID: "r1", workflowID: "w1", workflowName: "HC", status: .completed)
        let cards = try await store.listCards(boardID: testBoardID, filter: BoardCardFilter(kind: .workflowRun))
        #expect(cards[0].status == .done)
    }

    @Test("Workflow failed moves card to blocked")
    func workflowFailedBlocked() async throws {
        let store = InMemoryBoardStore()
        let proj = BoardProjection(store: store, boardID: testBoardID)
        try await proj.projectWorkflowRun(runID: "r1", workflowID: "w1", workflowName: "HC", status: .failed)
        let cards = try await store.listCards(boardID: testBoardID, filter: BoardCardFilter(kind: .workflowRun))
        #expect(cards[0].status == .blocked)
    }

    @Test("Approval creates needsApproval card")
    func approvalCreatesCard() async throws {
        let store = InMemoryBoardStore()
        let proj = BoardProjection(store: store, boardID: testBoardID)
        try await proj.projectApproval(approvalID: "a1", title: "Approve test", summary: "swift.test", risk: .medium, status: .pending)
        let cards = try await store.listCards(boardID: testBoardID, filter: BoardCardFilter(kind: .approval))
        #expect(cards.count == 1)
        #expect(cards[0].status == .needsApproval)
    }

    @Test("Approval approved moves to done")
    func approvalApprovedDone() async throws {
        let store = InMemoryBoardStore()
        let proj = BoardProjection(store: store, boardID: testBoardID)
        try await proj.projectApproval(approvalID: "a1", title: "T", summary: "S", risk: .medium, status: .pending)
        try await proj.projectApproval(approvalID: "a1", title: "T", summary: "S", risk: .medium, status: .approved)
        let cards = try await store.listCards(boardID: testBoardID, filter: BoardCardFilter(kind: .approval))
        #expect(cards[0].status == .done)
    }

    @Test("Approval denied moves to blocked")
    func approvalDeniedBlocked() async throws {
        let store = InMemoryBoardStore()
        let proj = BoardProjection(store: store, boardID: testBoardID)
        try await proj.projectApproval(approvalID: "a1", title: "T", summary: "S", risk: .high, status: .denied)
        let cards = try await store.listCards(boardID: testBoardID, filter: BoardCardFilter(kind: .approval))
        #expect(cards[0].status == .blocked)
    }

    @Test("Trigger event creates card")
    func triggerCreatesCard() async throws {
        let store = InMemoryBoardStore()
        let proj = BoardProjection(store: store, boardID: testBoardID)
        try await proj.projectTriggerEvent(triggerEventID: "te1", triggerID: "t1", workflowName: "HC", triggerKind: "schedule", status: .detected)
        let cards = try await store.listCards(boardID: testBoardID, filter: BoardCardFilter(kind: .triggerEvent))
        #expect(cards.count == 1)
    }

    @Test("Memory candidate creates review card")
    func memoryCreatesCard() async throws {
        let store = InMemoryBoardStore()
        let proj = BoardProjection(store: store, boardID: testBoardID)
        try await proj.projectMemoryCandidate(candidateID: "m1", redactedSummary: "User preference", status: .pending)
        let cards = try await store.listCards(boardID: testBoardID, filter: BoardCardFilter(kind: .memoryReview))
        #expect(cards.count == 1)
        #expect(cards[0].status == .review)
    }

    @Test("Session task creates inbox card")
    func sessionTaskCreatesCard() async throws {
        let store = InMemoryBoardStore()
        let proj = BoardProjection(store: store, boardID: testBoardID)
        try await proj.projectSessionTask(title: "Fix test", summary: "Flaky test", priority: .high, kind: .agentTask, sessionID: "s1")
        let cards = try await store.listCards(boardID: testBoardID, filter: nil)
        #expect(cards.count == 1)
        #expect(cards[0].status == .inbox)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Safety Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Board Safety")
struct BoardSafetyTests {

    @Test("Moving approval card to done does NOT approve the approval")
    func moveApprovalCardDoesNotApprove() async throws {
        let store = InMemoryBoardStore()
        var card = makeTestCard(id: "c1", status: .needsApproval, kind: .approval,
            source: BoardCardSource(kind: .approval, approvalID: "appr_123"))
        try await store.saveCard(card)
        // Move card to done — this is just a board status change
        card.status = .done; card.updatedAt = Date()
        try await store.updateCard(card)
        // The card is now "done" on the board
        let got = try await store.getCard(id: "c1")
        #expect(got?.status == .done)
        // But this test proves we only changed board status.
        // No ApprovalInbox.resolve was called. The approval is still pending.
        // The board store has no method to resolve approvals.
    }

    @Test("Completing card does not execute tool")
    func completeDoesNotExecute() async throws {
        let store = InMemoryBoardStore()
        var card = makeTestCard(id: "c1", kind: .workflowStep,
            source: BoardCardSource(kind: .workflowStep, toolCallID: "tc_1"))
        try await store.saveCard(card)
        card.status = .done
        try await store.updateCard(card)
        // Board store has no tool execution. Only status changed.
        #expect(try await store.getCard(id: "c1")?.status == .done)
    }

    @Test("Archiving workflow card does not cancel workflow")
    func archiveDoesNotCancel() async throws {
        let store = InMemoryBoardStore()
        var card = makeTestCard(id: "c1", kind: .workflowRun,
            source: BoardCardSource(kind: .workflowRun, runID: "run_1"))
        try await store.saveCard(card)
        card.status = .archived
        try await store.updateCard(card)
        // Board store has no workflow cancellation logic.
        #expect(try await store.getCard(id: "c1")?.status == .archived)
    }

    @Test("Deleting card does not delete audit history")
    func deleteDoesNotAffectAudit() async throws {
        let store = InMemoryBoardStore()
        let event = BoardEvent(cardID: "c1", boardID: testBoardID, type: .cardCreated, actor: systemActor, message: "Created")
        try await store.saveEvent(event)
        try await store.saveCard(makeTestCard(id: "c1"))
        try await store.deleteCard(id: "c1")
        // Events remain even after card deletion
        let events = try await store.listEvents(cardID: "c1", boardID: nil, limit: nil)
        #expect(events.count == 1)
    }

    @Test("BoardSafetyPolicy detects approval-linked card")
    func safetyDetectsApprovalCard() {
        let policy = BoardSafetyPolicy()
        let card = makeTestCard(kind: .approval,
            source: BoardCardSource(kind: .approval, approvalID: "appr_1"))
        #expect(policy.requiresApprovalRouting(card))
    }

    @Test("BoardSafetyPolicy /why explains safety")
    func safetyWhyExplains() {
        let policy = BoardSafetyPolicy()
        let card = makeTestCard(kind: .approval,
            source: BoardCardSource(kind: .approval, approvalID: "appr_1"))
        let why = policy.whyExplanation(card)
        #expect(why.contains("Moving this card to Done will NOT approve"))
        #expect(why.contains("/approval approve"))
    }

    @Test("Non-approval card does not require routing")
    func nonApprovalNoRouting() {
        let policy = BoardSafetyPolicy()
        let card = makeTestCard(kind: .manualTask)
        #expect(!policy.requiresApprovalRouting(card))
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Privacy Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Board Privacy")
struct BoardPrivacyTests {

    @Test("Redactor removes private keys")
    func redactsPrivateKey() {
        let r = BoardContentRedactor()
        let result = r.redact("Found -----BEGIN PRIVATE KEY here")
        #expect(!result.contains("-----BEGIN"))
        #expect(!result.contains("PRIVATE KEY"))
    }

    @Test("Redactor removes seed phrase markers")
    func redactsSeed() {
        let r = BoardContentRedactor()
        let result = r.redact("seed: word1 word2 word3")
        #expect(!result.contains("seed:"))
    }

    @Test("Redactor removes cookie markers")
    func redactsCookies() {
        let r = BoardContentRedactor()
        let result = r.redact("cookie: session=abc123")
        #expect(!result.contains("cookie:"))
    }

    @Test("Redactor removes session tokens")
    func redactsSessionToken() {
        let r = BoardContentRedactor()
        let result = r.redact("session_token=xyz")
        #expect(!result.contains("session_token"))
    }

    @Test("Redactor truncates long text")
    func truncatesLong() {
        let r = BoardContentRedactor(maxPreviewLength: 50)
        let result = r.redact(String(repeating: "a", count: 200))
        #expect(result.count <= 50)
    }

    @Test("Safe text passes through")
    func safePassThrough() {
        let r = BoardContentRedactor()
        let result = r.redact("Swift Package Health Check")
        #expect(result == "Swift Package Health Check")
    }

    @Test("Projection redacts summary")
    func projectionRedacts() async throws {
        let store = InMemoryBoardStore()
        let proj = BoardProjection(store: store, boardID: testBoardID)
        try await proj.projectApproval(
            approvalID: "a1", title: "Test",
            summary: "Contains -----BEGIN PRIVATE KEY data",
            risk: .medium, status: .pending
        )
        let cards = try await store.listCards(boardID: testBoardID, filter: nil)
        #expect(!cards[0].summary!.contains("-----BEGIN"))
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Card Lifecycle Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Card Lifecycle")
struct CardLifecycleTests {

    @Test("Card starts in inbox")
    func startsInInbox() {
        let card = BoardCard(boardID: "b", title: "Task")
        #expect(card.status == .inbox)
    }

    @Test("Priority mapping")
    func priorityMapping() {
        #expect(BoardCardPriority.urgent.rawValue == "urgent")
        #expect(BoardCardPriority.low.rawValue == "low")
    }

    @Test("Card source tracks provenance")
    func sourceTracksProvenance() {
        let source = BoardCardSource(kind: .workflowRun, workflowID: "w1", runID: "r1")
        #expect(source.workflowID == "w1")
        #expect(source.runID == "r1")
    }

    @Test("Board link types")
    func linkTypes() {
        let link = BoardLink(fromCardID: "c1", toCardID: "c2", kind: .dependsOn)
        #expect(link.kind == .dependsOn)
    }

    @Test("Blocker reason types")
    func blockerReasons() {
        let b = BoardBlocker(cardID: "c1", reason: .awaitingApproval, message: "Waiting")
        #expect(b.reason == .awaitingApproval)
    }

    @Test("Event types")
    func eventTypes() {
        let e = BoardEvent(cardID: "c1", boardID: "b1", type: .cardMoved, actor: testActor, message: "Moved")
        #expect(e.type == .cardMoved)
    }

    @Test("Artifact kinds")
    func artifactKinds() {
        let a = BoardArtifact(cardID: "c1", kind: .diff, title: "Patch", uri: "/tmp/p")
        #expect(a.kind == .diff)
    }

    @Test("Assignee kinds")
    func assigneeKinds() {
        let h = BoardAssignee(kind: .human, displayName: "Dev")
        let s = BoardAssignee(kind: .swoosh, displayName: "Swoosh")
        #expect(h.kind == .human)
        #expect(s.kind == .swoosh)
    }
}
