// Tests/SwooshPluginRuntimeTests/ExecutablePluginExecutorTests.swift — 0.8B

import Testing
import Foundation
@testable import SwooshPlugins
@testable import SwooshPluginRuntime
@testable import SwooshTools

private func makePluginsRoot() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("swoosh-exec-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Writes a tiny POSIX shell script to `<pluginsRoot>/<id>/main.sh`,
/// marks it executable, and returns the matching manifest.
@discardableResult
private func writeShellPlugin(
    id: String,
    script: String,
    timeoutSeconds: Int = 5,
    maxOutputBytes: Int = 16_000,
    in pluginsRoot: URL
) throws -> PluginManifest {
    let dir = pluginsRoot.appendingPathComponent(id, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let scriptURL = dir.appendingPathComponent("main.sh")
    try script.write(to: scriptURL, atomically: true, encoding: .utf8)
    let attrs: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
    try FileManager.default.setAttributes(attrs, ofItemAtPath: scriptURL.path)

    let manifest = PluginManifest(
        id: id, name: id, version: "1.0.0",
        kind: .executable,
        entrypoint: .executable(path: "main.sh", arguments: []),
        requestedPermissions: ["toolRead"],
        tools: [PluginToolManifest(
            name: "test.echo", description: "",
            permission: .toolRead, risk: .readOnly, requiresApproval: false
        )],
        sandbox: PluginSandboxPolicy(
            allowFilesystemRead: false, allowFilesystemWrite: false,
            allowNetwork: false, allowProcessSpawn: false,
            allowedRoots: [], maxOutputBytes: maxOutputBytes,
            timeoutSeconds: timeoutSeconds
        )
    )
    return manifest
}

@Suite("ExecutablePluginExecutor")
struct ExecutablePluginExecutorTests {

    @Test("happy-path JSON round-trip")
    func roundTrip() async throws {
        let root = makePluginsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try writeShellPlugin(
            id: "echo-plug",
            script: """
            #!/bin/sh
            cat >/dev/null
            printf '{"ok":true,"output":{"hello":"world"}}\n'
            """,
            in: root
        )
        let executor = ExecutablePluginExecutor(pluginsRoot: root)
        let result = try await executor.call(
            manifest: manifest, toolName: "test.echo",
            args: .object(["x": .int(1)]),
            context: ToolContext(sessionID: "t")
        )
        guard case .object(let dict) = result else {
            Issue.record("unexpected output: \(result)")
            return
        }
        #expect(dict["hello"] == JSONValue.string("world"))
    }

    @Test("timeout terminates a hanging plugin")
    func timeout() async throws {
        let root = makePluginsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try writeShellPlugin(
            id: "sleeper",
            script: """
            #!/bin/sh
            sleep 10
            printf '{"ok":true,"output":null}\n'
            """,
            timeoutSeconds: 1,
            in: root
        )
        let executor = ExecutablePluginExecutor(pluginsRoot: root)
        let start = Date()
        do {
            _ = try await executor.call(
                manifest: manifest, toolName: "test.echo",
                args: .null, context: ToolContext(sessionID: "t")
            )
            Issue.record("expected sandbox violation")
        } catch PluginError.sandboxViolation(let msg) {
            #expect(msg.contains("timeout"))
        }
        // Timeout should kill us well under 3s (1s timeout + grace).
        #expect(Date().timeIntervalSince(start) < 3.0)
    }

    @Test("max output bytes triggers sandbox violation")
    func outputCap() async throws {
        let root = makePluginsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try writeShellPlugin(
            id: "blabber",
            script: """
            #!/bin/sh
            cat >/dev/null
            # Print way more than the 1KB cap.
            yes "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" | head -c 4096
            """,
            maxOutputBytes: 1024,
            in: root
        )
        let executor = ExecutablePluginExecutor(pluginsRoot: root)
        do {
            _ = try await executor.call(
                manifest: manifest, toolName: "test.echo",
                args: .null, context: ToolContext(sessionID: "t")
            )
            Issue.record("expected sandbox violation")
        } catch PluginError.sandboxViolation(let msg) {
            #expect(msg.contains("maxOutputBytes"))
        }
    }

    @Test("malformed JSON output throws")
    func malformedOutput() async throws {
        let root = makePluginsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try writeShellPlugin(
            id: "bad",
            script: """
            #!/bin/sh
            cat >/dev/null
            printf 'not json at all\n'
            """,
            in: root
        )
        let executor = ExecutablePluginExecutor(pluginsRoot: root)
        do {
            _ = try await executor.call(
                manifest: manifest, toolName: "test.echo",
                args: .null, context: ToolContext(sessionID: "t")
            )
            Issue.record("expected sandbox violation")
        } catch PluginError.sandboxViolation(let msg) {
            #expect(msg.contains("malformed JSON"))
        }
    }

    @Test("structured error from plugin surfaces as toolFailed (not sandboxViolation)")
    func structuredError() async throws {
        let root = makePluginsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try writeShellPlugin(
            id: "fails",
            script: """
            #!/bin/sh
            cat >/dev/null
            printf '{"ok":false,"error":"intentional failure"}\n'
            """,
            in: root
        )
        let executor = ExecutablePluginExecutor(pluginsRoot: root)
        do {
            _ = try await executor.call(
                manifest: manifest, toolName: "test.echo",
                args: .null, context: ToolContext(sessionID: "t")
            )
            Issue.record("expected error")
        } catch PluginError.toolFailed(let msg) {
            #expect(msg.contains("intentional failure"))
        } catch {
            Issue.record("expected PluginError.toolFailed, got: \(error)")
        }
    }

    @Test("environment is scrubbed")
    func envScrubbed() async throws {
        // Set a non-allowed env var; the plugin's env should not contain it.
        setenv("SECRET_LEAK", "should-be-stripped", 1)
        setenv("SWOOSH_PLUGIN_OPT_IN", "passed-through", 1)
        defer {
            unsetenv("SECRET_LEAK")
            unsetenv("SWOOSH_PLUGIN_OPT_IN")
        }
        let root = makePluginsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try writeShellPlugin(
            id: "envcheck",
            script: """
            #!/bin/sh
            cat >/dev/null
            leak=${SECRET_LEAK:-missing}
            optin=${SWOOSH_PLUGIN_OPT_IN:-missing}
            printf '{"ok":true,"output":{"leak":"%s","optin":"%s"}}\n' "$leak" "$optin"
            """,
            in: root
        )
        let executor = ExecutablePluginExecutor(pluginsRoot: root)
        let result = try await executor.call(
            manifest: manifest, toolName: "test.echo",
            args: .null, context: ToolContext(sessionID: "t")
        )
        guard case .object(let dict) = result else { Issue.record("not object"); return }
        #expect(dict["leak"] == .string("missing"), "SECRET_LEAK should not be forwarded")
        #expect(dict["optin"] == .string("passed-through"), "SWOOSH_PLUGIN_* should be forwarded")
    }

    @Test("missing executable throws missingEntrypoint")
    func missingExecutable() async throws {
        let root = makePluginsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = PluginManifest(
            id: "ghost", name: "ghost", version: "1.0.0",
            kind: .executable,
            entrypoint: .executable(path: "nonexistent.sh", arguments: []),
            requestedPermissions: ["toolRead"],
            tools: [PluginToolManifest(
                name: "x", description: "",
                permission: .toolRead, risk: .readOnly, requiresApproval: false
            )]
        )
        let executor = ExecutablePluginExecutor(pluginsRoot: root)
        do {
            _ = try await executor.call(
                manifest: manifest, toolName: "x",
                args: .null, context: ToolContext(sessionID: "t")
            )
            Issue.record("expected missingEntrypoint")
        } catch PluginError.missingEntrypoint {
            // expected
        }
    }
}

@Suite("Bundled HelloExec manifest")
struct BundledHelloExecTests {
    private var manifestURL: URL {
        URL(fileURLWithPath: "Plugins/HelloExec/manifest.json")
    }

    @Test("manifest decodes and validates")
    func decodesAndValidates() throws {
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(PluginManifest.self, from: data)
        #expect(manifest.id == "hello-exec")
        #expect(manifest.kind == .executable)
        if case .executable(let path, _) = manifest.entrypoint {
            #expect(path == "main.sh")
        } else {
            Issue.record("expected executable entrypoint")
        }
        #expect(manifest.validate().isEmpty)
    }

    @Test("end-to-end through ExecutablePluginExecutor")
    func endToEnd() async throws {
        // Set up a temp plugins root and copy the bundled HelloExec into it
        // (the executor resolves relative paths against this root).
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-bundled-exec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("hello-exec", isDirectory: true)
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: "Plugins/HelloExec"),
            to: target
        )
        let manifestData = try Data(contentsOf: target.appendingPathComponent("manifest.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(PluginManifest.self, from: manifestData)

        let executor = ExecutablePluginExecutor(pluginsRoot: root)
        let result = try await executor.call(
            manifest: manifest, toolName: "exec.echo",
            args: .object(["message": .string("ping")]),
            context: ToolContext(sessionID: "t")
        )
        guard case .object(let dict) = result else { Issue.record("not object"); return }
        #expect(dict["pluginID"] == .string("hello-exec"))
        if case .object(let echoed) = dict["echoed"] ?? .null {
            #expect(echoed["message"] == .string("ping"))
        } else {
            Issue.record("echoed not an object: \(dict["echoed"] ?? .null)")
        }
    }
}
