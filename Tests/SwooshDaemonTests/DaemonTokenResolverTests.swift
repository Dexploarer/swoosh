import Foundation
import Testing
@testable import SwooshDaemonSupport

@Suite("Daemon token resolver")
struct DaemonTokenResolverTests {
    @Test("Environment token wins")
    func environmentTokenWins() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let token = try DaemonTokenResolver.resolve(
            swooshDir: dir,
            env: ["SWOOSH_API_TOKEN": "from-env"],
            tokenGenerator: { "generated" }
        )

        #expect(token == "from-env")
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("api_token").path))
    }

    @Test("Cached token wins over generator")
    func cachedTokenWins() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("from-file\n".utf8).write(to: dir.appendingPathComponent("api_token"))

        let token = try DaemonTokenResolver.resolve(
            swooshDir: dir,
            env: [:],
            tokenGenerator: { "generated" }
        )

        #expect(token == "from-file")
    }

    @Test("Generated token persists with user-only permissions")
    func generatedTokenPersists() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let token = try DaemonTokenResolver.resolve(
            swooshDir: dir,
            env: [:],
            tokenGenerator: { "generated" }
        )

        let tokenFile = dir.appendingPathComponent("api_token")
        let persisted = try String(contentsOf: tokenFile, encoding: .utf8)
        let attributes = try FileManager.default.attributesOfItem(atPath: tokenFile.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        #expect(token == "generated")
        #expect(persisted == "generated")
        #expect(permissions?.intValue == 0o600)
    }

    private func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-daemon-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
