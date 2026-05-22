// Tests/SwooshPluginRuntimeTests/WasmPluginExecutorTests.swift — 0.8B

import Testing
import Foundation
@testable import SwooshPlugins
@testable import SwooshPluginRuntime
@testable import SwooshTools

private func makePluginsRoot() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("swoosh-wasm-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func writeWatPlugin(
    id: String,
    wat: String,
    timeoutSeconds: Int = 5,
    in pluginsRoot: URL
) throws -> PluginManifest {
    let dir = pluginsRoot.appendingPathComponent(id, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try wat.write(
        to: dir.appendingPathComponent("plugin.wat"),
        atomically: true, encoding: .utf8
    )
    return PluginManifest(
        id: id, name: id, version: "1.0.0",
        kind: .wasm,
        entrypoint: .wasm(path: "plugin.wat"),
        requestedPermissions: ["toolRead"],
        tools: [PluginToolManifest(
            name: "wasm.add", description: "Add",
            permission: .toolRead, risk: .readOnly, requiresApproval: false
        )],
        sandbox: PluginSandboxPolicy(
            allowFilesystemRead: false, allowFilesystemWrite: false,
            allowNetwork: false, allowProcessSpawn: false,
            allowedRoots: [], maxOutputBytes: 4_000,
            timeoutSeconds: timeoutSeconds
        )
    )
}

private let addWAT = """
(module
  (func $add (export "add") (param $a i32) (param $b i32) (result i32)
    local.get $a
    local.get $b
    i32.add)
)
"""

@Suite("WasmPluginExecutor")
struct WasmPluginExecutorTests {

    @Test(".wat compiles and add returns sum")
    func addWorks() async throws {
        let root = makePluginsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try writeWatPlugin(id: "wat-add", wat: addWAT, in: root)
        let executor = WasmPluginExecutor(pluginsRoot: root)
        let result = try await executor.call(
            manifest: manifest, toolName: "wasm.add",
            args: .object(["a": .int(40), "b": .int(2)]),
            context: ToolContext(sessionID: "t")
        )
        guard case .object(let dict) = result else { Issue.record("not object"); return }
        #expect(dict["sum"] == JSONValue.int(42))
        #expect(dict["pluginID"] == JSONValue.string("wat-add"))
    }

    @Test("unknown tool throws toolNotRegistered")
    func unknownTool() async throws {
        let root = makePluginsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try writeWatPlugin(id: "wat-add", wat: addWAT, in: root)
        let executor = WasmPluginExecutor(pluginsRoot: root)
        do {
            _ = try await executor.call(
                manifest: manifest, toolName: "wasm.unknown",
                args: .null, context: ToolContext(sessionID: "t")
            )
            Issue.record("expected toolNotRegistered")
        } catch PluginError.toolNotRegistered {
            // expected
        }
    }

    @Test("missing wasm file throws missingEntrypoint")
    func missingFile() async throws {
        let root = makePluginsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("ghost"), withIntermediateDirectories: true
        )
        let manifest = PluginManifest(
            id: "ghost", name: "ghost", version: "1.0.0",
            kind: .wasm,
            entrypoint: .wasm(path: "missing.wasm"),
            requestedPermissions: ["toolRead"],
            tools: [PluginToolManifest(
                name: "wasm.add", description: "",
                permission: .toolRead, risk: .readOnly, requiresApproval: false
            )]
        )
        let executor = WasmPluginExecutor(pluginsRoot: root)
        do {
            _ = try await executor.call(
                manifest: manifest, toolName: "wasm.add",
                args: .object(["a": .int(1), "b": .int(2)]),
                context: ToolContext(sessionID: "t")
            )
            Issue.record("expected missingEntrypoint")
        } catch PluginError.missingEntrypoint {
            // expected
        }
    }

    @Test("malformed .wat throws sandboxViolation")
    func malformedWAT() async throws {
        let root = makePluginsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try writeWatPlugin(
            id: "broken",
            wat: "(this is not valid wat)",
            in: root
        )
        let executor = WasmPluginExecutor(pluginsRoot: root)
        do {
            _ = try await executor.call(
                manifest: manifest, toolName: "wasm.add",
                args: .object(["a": .int(1), "b": .int(2)]),
                context: ToolContext(sessionID: "t")
            )
            Issue.record("expected sandboxViolation")
        } catch PluginError.sandboxViolation {
            // expected
        }
    }

    @Test("non-numeric args throw sandboxViolation")
    func badArgs() async throws {
        let root = makePluginsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try writeWatPlugin(id: "wat-add", wat: addWAT, in: root)
        let executor = WasmPluginExecutor(pluginsRoot: root)
        do {
            _ = try await executor.call(
                manifest: manifest, toolName: "wasm.add",
                args: .object(["a": .string("not a number"), "b": .int(2)]),
                context: ToolContext(sessionID: "t")
            )
            Issue.record("expected sandboxViolation")
        } catch PluginError.sandboxViolation {
            // expected
        }
    }
}

@Suite("Bundled HelloWasm manifest")
struct BundledHelloWasmTests {
    private var manifestURL: URL {
        URL(fileURLWithPath: "Plugins/HelloWasm/manifest.json")
    }

    @Test("manifest decodes and validates")
    func decodesAndValidates() throws {
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(PluginManifest.self, from: data)
        #expect(manifest.id == "hello-wasm")
        #expect(manifest.kind == .wasm)
        if case .wasm(let path) = manifest.entrypoint {
            #expect(path == "plugin.wat")
        } else {
            Issue.record("expected wasm entrypoint")
        }
        #expect(manifest.validate().isEmpty)
    }

    @Test("end-to-end against the bundled .wat fixture")
    func endToEnd() async throws {
        // Copy the bundled HelloWasm dir into a temp root so the executor
        // can resolve the relative wat path against it.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-bundled-wasm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: "Plugins/HelloWasm"),
            to: root.appendingPathComponent("hello-wasm")
        )
        let manifestData = try Data(contentsOf: root.appendingPathComponent("hello-wasm/manifest.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(PluginManifest.self, from: manifestData)

        let executor = WasmPluginExecutor(pluginsRoot: root)
        let result = try await executor.call(
            manifest: manifest, toolName: "wasm.add",
            args: .object(["a": .int(3), "b": .int(4)]),
            context: ToolContext(sessionID: "t")
        )
        guard case .object(let dict) = result else { Issue.record("not object"); return }
        #expect(dict["sum"] == JSONValue.int(7))
        #expect(dict["pluginID"] == JSONValue.string("hello-wasm"))
    }
}
