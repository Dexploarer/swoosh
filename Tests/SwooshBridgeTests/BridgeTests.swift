// Tests/SwooshBridgeTests/BridgeTests.swift — SwooshBridge MCP / worker scaffolding
//
// SwooshBridge currently exposes data types + an MCPBridge actor whose
// network operations throw `transportUnavailable`. Tests cover the
// public surface that can be exercised without a real MCP server.

import Testing
import Foundation
@testable import SwooshBridge
@testable import SwooshTools

// MARK: - WorkerContext / WorkerResult

@Suite("WorkerContext")
struct WorkerContextTests {

    @Test("Defaults to current directory")
    func defaults() {
        let ctx = WorkerContext()
        #expect(ctx.environment.isEmpty)
        #expect(ctx.timeout == 60)
        // workingDirectory falls back to FileManager.currentDirectoryPath
        #expect(!ctx.workingDirectory.path.isEmpty)
    }

    @Test("Custom fields preserved")
    func customFields() {
        let url = URL(fileURLWithPath: "/tmp")
        let ctx = WorkerContext(workingDirectory: url, environment: ["K": "V"], timeout: 5)
        #expect(ctx.workingDirectory == url)
        #expect(ctx.environment["K"] == "V")
        #expect(ctx.timeout == 5)
    }
}

@Suite("WorkerResult")
struct WorkerResultTests {

    @Test("succeeded when exit code is zero")
    func succeededZero() {
        let r = WorkerResult(stdout: "ok")
        #expect(r.exitCode == 0)
        #expect(r.succeeded)
    }

    @Test("succeeded false for non-zero exit code")
    func failedNonZero() {
        let r = WorkerResult(stdout: "", stderr: "boom", exitCode: 2)
        #expect(r.succeeded == false)
    }
}

// MARK: - WorkerLanguage

@Suite("WorkerLanguage Codable")
struct WorkerLanguageTests {

    @Test("Codable round-trip")
    func roundTrip() throws {
        for lang in [WorkerLanguage.python, .node, .shell, .swift] {
            let data = try JSONEncoder().encode(lang)
            let decoded = try JSONDecoder().decode(WorkerLanguage.self, from: data)
            #expect(decoded == lang)
        }
    }

    @Test("Stable raw values")
    func raw() {
        #expect(WorkerLanguage.python.rawValue == "python")
        #expect(WorkerLanguage.node.rawValue == "node")
        #expect(WorkerLanguage.shell.rawValue == "shell")
        #expect(WorkerLanguage.swift.rawValue == "swift")
    }
}

// MARK: - MCPBridgeError

@Suite("MCPBridgeError")
struct MCPBridgeErrorTests {

    @Test("LocalizedError descriptions exist")
    func descriptions() {
        let transport = MCPBridgeError.transportUnavailable("import")
        let server = MCPBridgeError.serverNotImported("fs")

        #expect(transport.errorDescription?.contains("import") == true)
        #expect(server.errorDescription?.contains("fs") == true)
    }
}

// MARK: - MCPBridge

@Suite("MCPBridge")
struct MCPBridgeTests {

    @Test("New bridge has no servers and no tools")
    func empty() async {
        let bridge = MCPBridge()
        let tools = await bridge.allTools()
        #expect(tools.isEmpty)
    }

    @Test("importServer throws transportUnavailable")
    func importThrows() async {
        let bridge = MCPBridge()
        await #expect(throws: MCPBridgeError.self) {
            try await bridge.importServer(name: "fs", command: "/bin/true")
        }
    }

    @Test("exportAsServer throws transportUnavailable")
    func exportThrows() async {
        let bridge = MCPBridge()
        await #expect(throws: MCPBridgeError.self) {
            try await bridge.exportAsServer(tools: [], port: 1)
        }
    }

    @Test("generateSwiftWrapper throws when server not imported")
    func wrapperThrowsWhenMissing() async {
        let bridge = MCPBridge()
        do {
            _ = try await bridge.generateSwiftWrapper(for: "missing")
            Issue.record("expected error")
        } catch let MCPBridgeError.serverNotImported(name) {
            #expect(name == "missing")
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }
}
