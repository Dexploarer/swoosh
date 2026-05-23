// Tests/SwooshFilesTests/ApprovedRootBookmarkTests.swift — 0.4D
//
// Covers `ApprovedRoot.makeBookmark(from:)` + `SafeFileAccessor.resolveBookmark(id:)`:
//   • A bookmark-backed root resolves to a usable URL pointing at the
//     real directory (not the static absolutePath).
//   • A root with `bookmarkData: nil` resolves to absolutePath
//     (unchanged contract from 0.4C).
//   • A root with stale/garbage bookmark data falls through to
//     absolutePath instead of throwing.
//   • A root whose id is not in the store throws `rootNotApproved`.
//
// Tests hit the real filesystem (no mocks) per the path-safety test
// philosophy — bookmark resolution is impossible to validate against a
// FileManager mock.

import Foundation
import Testing
@testable import SwooshFiles

@Suite("ApprovedRoot bookmark resolution")
struct ApprovedRootBookmarkTests {

    private func tmpDir(_ name: String = UUID().uuidString) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-files-\(name)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("makeBookmark produces a non-empty bookmarkData")
    func makeBookmarkEncodes() throws {
        let dir = tmpDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try ApprovedRoot.makeBookmark(from: dir, displayName: "tmp")
        #expect(root.bookmarkData != nil)
        #expect(!(root.bookmarkData?.isEmpty ?? true))
        #expect(root.displayName == "tmp")
        #expect(root.absolutePath == dir.standardizedFileURL.path)
    }

    @Test("resolveBookmark prefers bookmark over absolutePath when present")
    func resolveBookmarkUsesBookmarkData() async throws {
        let dir = tmpDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let root = try ApprovedRoot.makeBookmark(from: dir, displayName: "tmp")
        let store = InMemoryRootStore()
        await store.add(root)

        let fa = SafeFileAccessor(rootStore: store)
        let resolved = try await fa.resolveBookmark(id: root.id)
        #expect(resolved.standardizedFileURL.path == dir.standardizedFileURL.path)
    }

    @Test("resolveBookmark falls back to absolutePath when bookmarkData is nil")
    func resolveBookmarkFallbackNoBookmark() async throws {
        let dir = tmpDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let root = ApprovedRoot(displayName: "tmp", bookmarkData: nil, absolutePath: dir.path)
        let store = InMemoryRootStore()
        await store.add(root)

        let fa = SafeFileAccessor(rootStore: store)
        let resolved = try await fa.resolveBookmark(id: root.id)
        #expect(resolved.path == dir.path)
    }

    @Test("resolveBookmark falls back to absolutePath when bookmarkData is garbage")
    func resolveBookmarkFallbackGarbage() async throws {
        let dir = tmpDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05])
        let root = ApprovedRoot(displayName: "tmp", bookmarkData: garbage, absolutePath: dir.path)
        let store = InMemoryRootStore()
        await store.add(root)

        let fa = SafeFileAccessor(rootStore: store)
        let resolved = try await fa.resolveBookmark(id: root.id)
        #expect(resolved.path == dir.path)
    }

    @Test("resolveBookmark throws rootNotApproved for unknown id")
    func resolveBookmarkUnknownId() async throws {
        let store = InMemoryRootStore()
        let fa = SafeFileAccessor(rootStore: store)
        do {
            _ = try await fa.resolveBookmark(id: "does-not-exist")
            Issue.record("expected throw")
        } catch let error as FileAccessError {
            #expect(error == .rootNotApproved)
        }
    }
}
