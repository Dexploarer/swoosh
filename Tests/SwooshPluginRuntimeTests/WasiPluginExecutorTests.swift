// Tests/SwooshPluginRuntimeTests/WasiPluginExecutorTests.swift — 0.8C

import Testing
import Foundation
@testable import SwooshPlugins
@testable import SwooshPluginRuntime
@testable import SwooshTools

private func tempRoot() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("swoosh-wasi-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func writeWasiPlugin(id: String, wat: String, in root: URL) throws -> PluginManifest {
    let dir = root.appendingPathComponent(id, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try wat.write(to: dir.appendingPathComponent("plugin.wat"),
                  atomically: true, encoding: .utf8)
    return PluginManifest(
        id: id, name: id, version: "1.0.0",
        kind: .wasm,
        entrypoint: .wasiWasm(path: "plugin.wat"),
        requestedPermissions: ["toolRead"],
        tools: [PluginToolManifest(
            name: "wasi.greet", description: "Greet via WASI stdout",
            permission: .toolRead, risk: .readOnly, requiresApproval: false
        )]
    )
}

private let greetWAT = """
(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 64) "{\\"hello\\":\\"wasi\\",\\"ok\\":true}")
  (func $_start (export "_start")
    i32.const 0
    i32.const 64
    i32.store
    i32.const 4
    i32.const 26
    i32.store
    i32.const 1
    i32.const 0
    i32.const 1
    i32.const 8
    call $fd_write
    drop)
)
"""

@Suite("WasmPluginExecutor — WASI mode")
struct WasiPluginExecutorTests {

    @Test("WASI module's stdout is parsed as response JSON")
    func wasiGreet() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try writeWasiPlugin(id: "wasi-greet", wat: greetWAT, in: root)
        let executor = WasmPluginExecutor(pluginsRoot: root)
        let result = try await executor.call(
            manifest: manifest, toolName: "wasi.greet",
            args: .object([:]),
            context: ToolContext(sessionID: "t")
        )
        guard case .object(let dict) = result else {
            Issue.record("expected object, got \(result)")
            return
        }
        #expect(dict["hello"] == JSONValue.string("wasi"))
        #expect(dict["ok"] == JSONValue.bool(true))
    }

    @Test("Repeated WASI calls don't leak file descriptors")
    func noFDLeak() async throws {
        // Each WASI call opens 3 pipes (6 FDs); if any are leaked we hit
        // EMFILE long before 200 iterations. The compile is cached after
        // the first call so this stays well under the test timeout.
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try writeWasiPlugin(id: "wasi-loop", wat: greetWAT, in: root)
        let executor = WasmPluginExecutor(pluginsRoot: root)
        for _ in 0..<200 {
            _ = try await executor.call(
                manifest: manifest, toolName: "wasi.greet",
                args: .null,
                context: ToolContext(sessionID: "t")
            )
        }
    }

    @Test("Validator accepts wasm kind with wasiWasm entrypoint")
    func validationAcceptsWasi() throws {
        let manifest = PluginManifest(
            id: "ok", name: "ok", version: "1.0",
            kind: .wasm, entrypoint: .wasiWasm(path: "plugin.wat"),
            requestedPermissions: ["toolRead"],
            tools: [PluginToolManifest(
                name: "wasi.greet", description: "",
                permission: .toolRead, risk: .readOnly, requiresApproval: false
            )]
        )
        #expect(manifest.validate().isEmpty)
    }
}

@Suite("Bundled HelloWasi manifest")
struct BundledHelloWasiTests {
    private var manifestURL: URL {
        URL(fileURLWithPath: "Plugins/HelloWasi/manifest.json")
    }

    @Test("manifest decodes and validates")
    func decodesAndValidates() throws {
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(PluginManifest.self, from: data)
        #expect(manifest.id == "hello-wasi")
        #expect(manifest.kind == .wasm)
        if case .wasiWasm(let path) = manifest.entrypoint {
            #expect(path == "plugin.wat")
        } else {
            Issue.record("expected wasiWasm entrypoint")
        }
        #expect(manifest.validate().isEmpty)
    }

    @Test("end-to-end against the bundled HelloWasi fixture")
    func endToEnd() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-bundled-wasi-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: "Plugins/HelloWasi"),
            to: root.appendingPathComponent("hello-wasi")
        )
        let manifestData = try Data(contentsOf: root.appendingPathComponent("hello-wasi/manifest.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(PluginManifest.self, from: manifestData)
        let executor = WasmPluginExecutor(pluginsRoot: root)
        let result = try await executor.call(
            manifest: manifest, toolName: "wasi.greet",
            args: .null,
            context: ToolContext(sessionID: "t")
        )
        guard case .object(let dict) = result else {
            Issue.record("expected object, got \(result)")
            return
        }
        #expect(dict["hello"] == JSONValue.string("wasi"))
        #expect(dict["ok"] == JSONValue.bool(true))
    }
}
