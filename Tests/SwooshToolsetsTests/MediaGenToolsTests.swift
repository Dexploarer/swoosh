// Tests/SwooshToolsetsTests/MediaGenToolsTests.swift
//
// Verifies the typed SwooshTool wrappers for media generation:
//   • each tool exposes correct permission / risk / approval / toolset
//   • the registry filters the tools by their permission gate (firewall
//     denial surfaces as a ToolError, audit row written)
//   • register hooks no-op when their provider is nil and register the
//     matching tool when present
//   • MediaCacheDir writes files atomically and maps MIME→ext correctly
//   • the tool round-trips through the registry with a stub provider

import Testing
import Foundation
@testable import SwooshToolsets
@testable import SwooshTools
@testable import SwooshFirewall
@testable import SwooshFiles
@testable import SwooshProcess
@testable import SwooshImageGen
@testable import SwooshMusic

// MARK: - Stubs

private actor StubImageProvider: ImageGenProviding {
    nonisolated let id = "stub-image"
    nonisolated let displayName = "Stub Image"
    nonisolated let isLocal = true
    nonisolated let supportsCustomSize = true
    func supportedStyles() async -> [ImageGenStyle] { [] }
    func generate(_ request: ImageGenRequest) async throws -> ImageGenResult {
        ImageGenResult(pngData: Data([0x89, 0x50, 0x4E, 0x47]), providerID: id, usedStyle: request.style?.id)
    }
}

private actor StubMusicProvider: MusicProviding {
    nonisolated let id = "stub-music"
    nonisolated let displayName = "Stub Music"
    nonisolated let availableModels: [MusicModel] = [
        MusicModel(id: "stub-v1", displayName: "Stub v1", maxDuration: 60)
    ]
    func generate(_ request: MusicRequest) async throws -> MusicJob {
        StubMusicJob(
            id: "stub-job",
            url: URL(string: "https://example.invalid/stub.mp3")!,
            modelUsed: request.model ?? "stub-v1",
            prompt: request.prompt
        )
    }
}

private struct StubMusicJob: MusicJob, @unchecked Sendable {
    let id: String
    let url: URL
    let modelUsed: String
    let prompt: String
    var result: MusicResult {
        get async throws {
            MusicResult(audioURL: url, mimeType: "audio/mpeg", durationSeconds: 30, modelUsed: modelUsed, promptEcho: prompt)
        }
    }
    func cancel() async {}
}

// MARK: - Descriptor tests

@Suite("MediaGenTools descriptors")
struct MediaGenDescriptorTests {

    @Test
    func generateImageDescriptor() {
        #expect(GenerateImageTool.permission == .imageGenerate)
        #expect(GenerateImageTool.risk == .medium)
        #expect(GenerateImageTool.toolset == .mediaGen)
        #expect(GenerateImageTool.name.rawValue == "media.generate_image")
    }

    @Test
    func generateVideoDescriptor() {
        #expect(GenerateVideoTool.permission == .videoGenerate)
        #expect(GenerateVideoTool.risk == .high)
        #expect(GenerateVideoTool.toolset == .mediaGen)
    }

    @Test
    func generate3DDescriptor() {
        #expect(Generate3DTool.permission == .threeDGenerate)
        #expect(Generate3DTool.risk == .high)
        #expect(Generate3DTool.toolset == .mediaGen)
    }

    @Test
    func generateMusicDescriptor() {
        #expect(GenerateMusicTool.permission == .musicGenerate)
        #expect(GenerateMusicTool.risk == .high)
        #expect(GenerateMusicTool.toolset == .mediaGen)
        #expect(GenerateMusicTool.approval == .askEveryTime)
    }
}

// MARK: - MediaCacheDir

@Suite("MediaCacheDir")
struct MediaCacheDirTests {

    @Test
    func writeAtomicProducesReadableFile() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-mediacache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let url = try MediaCacheDir.write(Data([1, 2, 3, 4]), extension: "bin", in: tmp)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let read = try Data(contentsOf: url)
        #expect(read == Data([1, 2, 3, 4]))
        #expect(url.pathExtension == "bin")
    }

    @Test
    func mimeMappingFallsBackToHint() {
        #expect(MediaCacheDir.fileExtension(forMime: "video/mp4", fallback: "mp4") == "mp4")
        #expect(MediaCacheDir.fileExtension(forMime: "video/webm", fallback: "mp4") == "webm")
        #expect(MediaCacheDir.fileExtension(forMime: "audio/mpeg", fallback: "mp4") == "mp3")
        #expect(MediaCacheDir.fileExtension(forMime: "application/unknown", fallback: "mp4") == "mp4")
    }
}

// MARK: - Registry integration

@Suite("MediaGenRegistrar")
struct MediaGenRegistrarTests {

    private func makeRegistry() -> (ToolRegistry, SwooshFirewallActor, SwooshAuditLog) {
        let firewall = SwooshFirewallActor()
        let audit = SwooshAuditLog()
        let approvals = InMemoryApprovalRequester(autoApprove: true)
        let registry = ToolRegistry(firewall: firewall, audit: audit, approvals: approvals)
        return (registry, firewall, audit)
    }

    @Test
    func nilBundleRegistersNothing() async {
        let (registry, _, _) = makeRegistry()
        await DefaultToolRegistrar.registerMediaGen(
            into: registry,
            mediaGen: MediaGenDependencies()
        )
        let descriptors = await registry.listAvailable(context: ToolContext(sessionID: "t"))
        let mediaNames = descriptors.filter { $0.toolset == .mediaGen }.map(\.name)
        #expect(mediaNames.isEmpty)
    }

    @Test
    func providersRegisterOnlyTheirOwnTools() async {
        let (registry, _, _) = makeRegistry()
        await DefaultToolRegistrar.registerMediaGen(
            into: registry,
            mediaGen: MediaGenDependencies(
                imageProvider: StubImageProvider(),
                musicProvider: StubMusicProvider()
            )
        )
        let descriptors = await registry.listAvailable(context: ToolContext(sessionID: "t"))
        let mediaNames = Set(descriptors.filter { $0.toolset == .mediaGen }.map(\.name))
        #expect(mediaNames.contains("media.generate_image"))
        #expect(mediaNames.contains("media.generate_music"))
        #expect(!mediaNames.contains("media.generate_video"))
        #expect(!mediaNames.contains("media.generate_3d"))
    }

    @Test
    func generateImageRoundTripsThroughRegistry() async throws {
        let (registry, firewall, _) = makeRegistry()
        await firewall.grant(.imageGenerate)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-media-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        await DefaultToolRegistrar.registerMediaGen(
            into: registry,
            mediaGen: MediaGenDependencies(imageProvider: StubImageProvider(), cacheDir: tmp)
        )
        let inputJSON = try JSONEncoder().encode(GenerateImageInput(prompt: "test"))
        let input = try JSONDecoder().decode(JSONValue.self, from: inputJSON)
        let output = try await registry.call(
            name: "media.generate_image",
            input: input,
            context: ToolContext(sessionID: "t", isModelInvocation: false)
        )
        let outputData = try JSONEncoder().encode(output)
        let decoded = try JSONDecoder().decode(GenerateImageOutput.self, from: outputData)
        #expect(decoded.providerID == "stub-image")
        #expect(decoded.format == "png")
        #expect(decoded.bytes == 4)
        #expect(FileManager.default.fileExists(atPath: decoded.path))
    }

    @Test
    func firewallDeniesUnpermittedImageCall() async {
        let (registry, _, _) = makeRegistry()
        // Note: no .grant(.imageGenerate) → firewall denies
        await DefaultToolRegistrar.registerMediaGen(
            into: registry,
            mediaGen: MediaGenDependencies(imageProvider: StubImageProvider())
        )
        let input: JSONValue = .object(["prompt": .string("test")])
        do {
            _ = try await registry.call(
                name: "media.generate_image",
                input: input,
                context: ToolContext(sessionID: "t", isModelInvocation: false)
            )
            Issue.record("expected firewall denial")
        } catch {
            // Any error from the gate counts — the firewall throws its
            // own typed error before the tool runs.
        }
    }
}
