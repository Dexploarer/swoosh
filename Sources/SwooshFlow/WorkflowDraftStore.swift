// SwooshFlow/WorkflowDraftStore.swift — In-memory draft storage (0.5A)

import Foundation

public protocol WorkflowDraftStoring: Sendable {
    func saveDraft(_ draft: WorkflowDraft05A) async throws
    func getDraft(id: String) async throws -> WorkflowDraft05A?
    func listDrafts(status: WorkflowDraftStatus?) async throws -> [WorkflowDraft05A]
    func updateDraft(_ draft: WorkflowDraft05A) async throws
    func deleteDraft(id: String) async throws
}

public actor InMemoryWorkflowDraftStore: WorkflowDraftStoring {
    private var drafts: [String: WorkflowDraft05A] = [:]
    public init() {}

    public func saveDraft(_ draft: WorkflowDraft05A) { drafts[draft.id] = draft }
    public func getDraft(id: String) -> WorkflowDraft05A? { drafts[id] }
    public func listDrafts(status: WorkflowDraftStatus?) -> [WorkflowDraft05A] {
        let all = Array(drafts.values)
        if let s = status { return all.filter { $0.status == s } }
        return all.sorted { $0.createdAt > $1.createdAt }
    }
    public func updateDraft(_ draft: WorkflowDraft05A) throws {
        guard drafts[draft.id] != nil else { throw WorkflowStoreError.notFound(draft.id) }
        drafts[draft.id] = draft
    }
    public func deleteDraft(id: String) throws {
        guard drafts[id] != nil else { throw WorkflowStoreError.notFound(id) }
        drafts.removeValue(forKey: id)
    }
}

public enum WorkflowStoreError: Error, Sendable {
    case notFound(String)
    case saveFailed(String)
}
