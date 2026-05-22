// Tests/SwooshLocalVoiceTests/LocalVoiceCloneStoreTests.swift
// Version: 0.9R
//
// Round-trip tests for the persistent clone store. Uses a per-test
// temp dir so runs are isolated and cleanup is automatic.

import XCTest
@testable import SwooshLocalVoice

final class LocalVoiceCloneStoreTests: XCTestCase {

    var tempRoot: URL!
    var store: LocalVoiceCloneStore!

    override func setUp() async throws {
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swoosh-clones-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        store = LocalVoiceCloneStore(root: tempRoot)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    // MARK: - Slug

    func test_slug_normalisesInput() {
        XCTAssertEqual(LocalVoiceCloneStore.slug(from: "My Voice"), "my-voice")
        XCTAssertEqual(LocalVoiceCloneStore.slug(from: "Alice's Clone!"), "alices-clone")
        XCTAssertEqual(LocalVoiceCloneStore.slug(from: "  trim  spaces  "), "trim-spaces")
        XCTAssertEqual(LocalVoiceCloneStore.slug(from: "snake_case_name"), "snake-case-name")
    }

    func test_slug_emptyInputGetsUUIDFallback() {
        let s = LocalVoiceCloneStore.slug(from: "@@@")
        XCTAssertTrue(s.hasPrefix("voice-"), "Empty slug must fall back to voice-<uuid> (got \(s))")
    }

    // MARK: - Add / list / fetch

    func test_addAndList_roundTrip() async throws {
        let bytes = Data("fake-voice-data".utf8)
        let record = try await store.add(name: "Test Voice", voiceDataBytes: bytes)
        XCTAssertEqual(record.id, "test-voice")
        XCTAssertEqual(record.name, "Test Voice")

        let all = try await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, "test-voice")

        let bytesBack = try await store.voiceDataBytes(id: "test-voice")
        XCTAssertEqual(bytesBack, bytes)
    }

    func test_add_persistsAcrossInstances() async throws {
        let bytes = Data("persist-me".utf8)
        _ = try await store.add(name: "Persistent", voiceDataBytes: bytes)

        // Spin up a second store rooted at the same dir — must see the entry.
        let store2 = LocalVoiceCloneStore(root: tempRoot)
        let all = try await store2.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, "persistent")
        let b2 = try await store2.voiceDataBytes(id: "persistent")
        XCTAssertEqual(b2, bytes)
    }

    func test_delete_removesRecordAndBlob() async throws {
        let bytes = Data("to-be-deleted".utf8)
        _ = try await store.add(name: "Doomed", voiceDataBytes: bytes)
        let bytesBefore = try await store.voiceDataBytes(id: "doomed")
        XCTAssertNotNil(bytesBefore)

        try await store.delete(id: "doomed")
        let bytesAfter = try await store.voiceDataBytes(id: "doomed")
        XCTAssertNil(bytesAfter)
        let allAfter = try await store.all()
        XCTAssertEqual(allAfter.count, 0)

        // Idempotent — deleting again must not throw.
        try await store.delete(id: "doomed")
    }

    func test_referenceAudio_isCopiedAndPreserved() async throws {
        // Create a synthetic reference file outside the store, add a clone
        // pointing at it, then delete the original — the store must still
        // expose its copied reference URL.
        let externalRef = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ext-\(UUID().uuidString).wav")
        try Data("reference-audio".utf8).write(to: externalRef)

        let record = try await store.add(
            name: "With Reference",
            voiceDataBytes: Data("vd".utf8),
            referenceAudio: externalRef,
            durationSeconds: 3.2
        )
        XCTAssertNotNil(record.referenceURL)
        XCTAssertEqual(record.durationSeconds, 3.2)

        try? FileManager.default.removeItem(at: externalRef)
        let savedRef = try await store.referenceAudioURL(id: record.id)
        XCTAssertNotNil(savedRef)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: savedRef!.path),
            "Reference audio must survive deletion of the source file"
        )
    }

    // MARK: - URL helper

    func test_voiceDataURL_isNonisolatedAndDeterministic() async throws {
        // voiceDataURL is nonisolated so callers (UI) can compute paths
        // without hitting the actor. It must produce a stable URL even
        // before the file exists.
        let u = store.voiceDataURL(id: "anything")
        XCTAssertTrue(u.path.hasSuffix("anything.voicedata"))
    }
}
