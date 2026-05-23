// Tests/SwooshFilesTests/SafeFileAccessorBoundsTests.swift — 0.4D
//
// Pins the three "denial of service" guards added in 0.4D:
//   • `searchFiles` skips files larger than `maxFileSize` instead of
//     loading them into memory (mirrors `readFile`'s guard).
//   • `listDirectory` clamps caller-supplied `maxDepth` to
//     `SafeFileAccessor.maxRecursiveDepth` (32) so an unbounded value
//     can't walk the stack.
//   • `deleteFile` throws the new `.deletionUnsupported` error case
//     instead of overloading `.writeNotAllowed`.

import Foundation
import Testing
@testable import SwooshFiles

@Suite("SafeFileAccessor bounds & guards")
struct SafeFileAccessorBoundsTests {

    private func freshRoot(_ tag: String = UUID().uuidString) throws -> (URL, ApprovedRoot, InMemoryRootStore) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-files-bounds-\(tag)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let root = ApprovedRoot(displayName: "tmp", absolutePath: dir.path)
        let store = InMemoryRootStore()
        return (dir, root, store)
    }

    // MARK: - searchFiles size guard

    @Test("searchFiles skips files above maxFileSize without loading them")
    func searchSkipsLargeFiles() async throws {
        let (dir, root, store) = try freshRoot()
        defer { try? FileManager.default.removeItem(at: dir) }
        await store.add(root)

        // Tiny file matches but a giant sibling would OOM us if read.
        let small = dir.appendingPathComponent("small.txt")
        try "needle in here".write(to: small, atomically: true, encoding: .utf8)

        // Manufacture a file larger than the configured maxFileSize.
        let huge = dir.appendingPathComponent("huge.txt")
        let chunk = Data(repeating: 0x41, count: 1024)
        FileManager.default.createFile(atPath: huge.path, contents: nil)
        let handle = try FileHandle(forWritingTo: huge)
        for _ in 0..<256 { handle.write(chunk) }
        try handle.close()
        // huge.txt is 256 KB; configure maxFileSize to 64 KB so it's over budget.

        let fa = SafeFileAccessor(rootStore: store, maxFileSize: 64 * 1024)
        let results = try await fa.searchFiles(
            root: URL(fileURLWithPath: root.absolutePath),
            query: "needle",
            filePattern: nil,
            maxResults: 10
        )
        #expect(results.count == 1)
        #expect(results.first?.relativePath == "small.txt")
    }

    @Test("searchFiles respects the configured maxResults limit")
    func searchHonoursMaxResults() async throws {
        let (dir, root, store) = try freshRoot()
        defer { try? FileManager.default.removeItem(at: dir) }
        await store.add(root)

        for i in 0..<10 {
            let url = dir.appendingPathComponent("file-\(i).txt")
            try "match-\(i)".write(to: url, atomically: true, encoding: .utf8)
        }
        let fa = SafeFileAccessor(rootStore: store)
        let results = try await fa.searchFiles(
            root: URL(fileURLWithPath: root.absolutePath),
            query: "match",
            filePattern: nil,
            maxResults: 3
        )
        #expect(results.count == 3)
    }

    // MARK: - listDirectory depth clamp

    @Test("listDirectory clamps unbounded maxDepth to the static cap")
    func listClampsDepth() async throws {
        let (dir, root, store) = try freshRoot()
        defer { try? FileManager.default.removeItem(at: dir) }
        await store.add(root)

        // Build a 40-deep chain. With the 32-recursion-level cap,
        // the deepest visible relativePath has `cap + 1` components
        // (root's children count as +1).
        var current = dir
        let depth = 40
        for i in 0..<depth {
            current.appendPathComponent("d\(i)")
            try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        }

        let fa = SafeFileAccessor(rootStore: store)
        let entries = try await fa.listDirectory(
            root: URL(fileURLWithPath: root.absolutePath),
            relativePath: nil,
            includeHidden: false,
            maxDepth: 9999
        )
        let deepest = entries
            .map { $0.relativePath.split(separator: "/").count }
            .max() ?? 0
        // The runtime cap is N recursion levels, which corresponds to
        // relativePaths of up to N + 1 components.
        #expect(deepest <= SafeFileAccessor.maxRecursiveDepth + 1)
        #expect(deepest > 0)
    }

    @Test("listDirectory with maxDepth: 0 returns only direct children")
    func listShallowDepth() async throws {
        let (dir, root, store) = try freshRoot()
        defer { try? FileManager.default.removeItem(at: dir) }
        await store.add(root)

        let a = dir.appendingPathComponent("a", isDirectory: true)
        let b = a.appendingPathComponent("b", isDirectory: true)
        let c = b.appendingPathComponent("c", isDirectory: true)
        try FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)

        let fa = SafeFileAccessor(rootStore: store)
        let entries = try await fa.listDirectory(
            root: URL(fileURLWithPath: root.absolutePath),
            relativePath: nil,
            includeHidden: false,
            maxDepth: 0
        )
        // maxDepth: 0 means "list this directory's children, recurse 0
        // levels" — so `a` is visible but `a/b` and `a/b/c` are not.
        #expect(entries.contains(where: { $0.relativePath == "a" }))
        #expect(!entries.contains(where: { $0.relativePath == "a/b" }))
        #expect(!entries.contains(where: { $0.relativePath == "a/b/c" }))
    }

    // MARK: - deleteFile error refinement

    @Test("deleteFile surfaces the new deletionUnsupported error")
    func deleteThrowsDeletionUnsupported() async throws {
        let (dir, root, store) = try freshRoot()
        defer { try? FileManager.default.removeItem(at: dir) }
        await store.add(root)

        let target = dir.appendingPathComponent("scratch.txt")
        try "data".write(to: target, atomically: true, encoding: .utf8)

        let fa = SafeFileAccessor(rootStore: store)
        do {
            try await fa.deleteFile(
                root: URL(fileURLWithPath: root.absolutePath),
                relativePath: "scratch.txt"
            )
            Issue.record("expected throw")
        } catch let error as FileAccessError {
            #expect(error == .deletionUnsupported)
            #expect(error != .writeNotAllowed)
        }
        // File must still exist — deletion never happened.
        #expect(FileManager.default.fileExists(atPath: target.path))
    }
}
