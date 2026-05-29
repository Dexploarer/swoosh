// SwooshUI/Dashboard/MemoryApproval.swift — Shared memory-candidate approval actions — 0.9Y
//
// Single source of truth for approving/rejecting Scout memory candidates,
// used by both MemoriesPane (per-row + Approve All) and the dashboard toast.
// Approve-All runs with bounded concurrency so a 100s-of-candidates backlog
// doesn't serialize into a dead UI; partial failures are counted, not hidden.

import Foundation
import SwooshClient

enum MemoryApproval {
    struct BulkResult: Sendable {
        var approved: Int
        var failed: Int
    }

    /// Approve many candidates with bounded concurrency. `progress` is invoked on
    /// the main actor after each completion with the running approved count so the
    /// caller can show "approved N of M" without coupling to the network layer.
    static func approveAll(
        ids: [String],
        client: SwooshAPIClient,
        concurrency: Int = 8,
        progress: @MainActor @Sendable (Int) -> Void = { _ in }
    ) async -> BulkResult {
        guard !ids.isEmpty else { return BulkResult(approved: 0, failed: 0) }
        var approved = 0
        var failed = 0
        var next = 0
        await withTaskGroup(of: Bool.self) { group in
            func addTask() {
                guard next < ids.count else { return }
                let id = ids[next]
                next += 1
                group.addTask {
                    do { _ = try await client.approveMemory(id: id); return true }
                    catch { return false }
                }
            }
            for _ in 0..<min(concurrency, ids.count) { addTask() }
            for await ok in group {
                if ok { approved += 1 } else { failed += 1 }
                let done = approved
                await progress(done)
                addTask()
            }
        }
        return BulkResult(approved: approved, failed: failed)
    }
}
