// Tests/SwooshPluginRuntimeTests/SBPLProfileTests.swift — 0.8C

import Testing
import Foundation
@testable import SwooshPlugins
@testable import SwooshPluginRuntime
@testable import SwooshTools

@Suite("SBPLProfileBuilder")
struct SBPLProfileBuilderTests {

    @Test("Generated profile denies network by default")
    func denyNetworkByDefault() {
        let profile = SBPLProfileBuilder.profile(
            pluginDir: URL(fileURLWithPath: "/tmp/dummy"),
            allowNetwork: false,
            allowFilesystemWrite: false,
            allowedRoots: []
        )
        #expect(profile.contains("(allow default)"))
        #expect(profile.contains("(deny network*)"))
    }

    @Test("Allow-network opt-in omits the deny rule")
    func allowNetworkOptIn() {
        let profile = SBPLProfileBuilder.profile(
            pluginDir: URL(fileURLWithPath: "/tmp/dummy"),
            allowNetwork: true,
            allowFilesystemWrite: false,
            allowedRoots: []
        )
        // Under allow-default we just *don't* deny network — there's no
        // separate allow rule to emit.
        #expect(!profile.contains("(deny network*)"))
        #expect(profile.contains("(allow default)"))
    }

    @Test("Plugin dir is in read subpaths")
    func pluginDirReadable() {
        let profile = SBPLProfileBuilder.profile(
            pluginDir: URL(fileURLWithPath: "/Users/foo/.swoosh/plugins/hello"),
            allowNetwork: false,
            allowFilesystemWrite: false,
            allowedRoots: []
        )
        #expect(profile.contains("/Users/foo/.swoosh/plugins/hello"))
    }

    @Test("FilesystemWrite gate omits deny-file-write* when writes are allowed")
    func writeGate() {
        let writable = SBPLProfileBuilder.profile(
            pluginDir: URL(fileURLWithPath: "/Users/foo/.swoosh/plugins/x"),
            allowNetwork: false, allowFilesystemWrite: true, allowedRoots: []
        )
        let readonly = SBPLProfileBuilder.profile(
            pluginDir: URL(fileURLWithPath: "/Users/foo/.swoosh/plugins/x"),
            allowNetwork: false, allowFilesystemWrite: false, allowedRoots: []
        )
        // With allowFilesystemWrite=true the deny-file-write* line is
        // omitted entirely (writes go through the allow-default).
        #expect(!writable.contains("(deny file-write*)"))
        // With allowFilesystemWrite=false the deny appears and an
        // allowlist re-opens just /tmp and the plugin dir.
        #expect(readonly.contains("(deny file-write*)"))
        #expect(readonly.contains("/Users/foo/.swoosh/plugins/x"))
    }

    @Test("Profile escapes paths with quotes")
    func escapesQuotes() {
        let profile = SBPLProfileBuilder.profile(
            pluginDir: URL(fileURLWithPath: "/tmp/has\"quote"),
            allowNetwork: false, allowFilesystemWrite: false, allowedRoots: []
        )
        // Embedded quote should be backslash-escaped, not raw.
        #expect(profile.contains("has\\\"quote") || !profile.contains("has\"quote\""))
    }

    @Test("sandbox-exec presence detected on macOS")
    func sandboxExecAvailable() {
        #if os(macOS)
        #expect(SBPLProfileBuilder.isAvailable)
        #else
        #expect(!SBPLProfileBuilder.isAvailable)
        #endif
    }
}

#if os(macOS)
@Suite("ExecutablePluginExecutor sandbox-exec")
struct ExecutablePluginExecutorSandboxTests {
    private func makePluginsRoot() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-sbpl-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func writeScript(_ script: String, name: String = "main.sh", id: String, in root: URL) throws -> PluginManifest {
        let dir = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return PluginManifest(
            id: id, name: id, version: "1.0",
            kind: .executable,
            entrypoint: .executable(path: name, arguments: []),
            requestedPermissions: ["toolRead"],
            tools: [PluginToolManifest(
                name: "exec.test", description: "",
                permission: .toolRead, risk: .readOnly, requiresApproval: false
            )]
        )
    }

    @Test("network denial reaches the plugin process")
    func networkDenied() async throws {
        let root = makePluginsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        // Plugin attempts a TCP connect via curl. With sandbox-exec
        // denying network*, the connect fails — curl exits non-zero —
        // and the plugin reports ok:false to the host.
        let manifest = try writeScript(
            """
            #!/bin/sh
            cat >/dev/null
            if curl -s --connect-timeout 2 -o /dev/null http://example.com 2>/dev/null; then
                printf '{"ok":true,"output":{"net":"reachable"}}\n'
            else
                printf '{"ok":true,"output":{"net":"blocked"}}\n'
            fi
            """,
            id: "netcheck",
            in: root
        )
        let executor = ExecutablePluginExecutor(pluginsRoot: root)
        let result = try await executor.call(
            manifest: manifest, toolName: "exec.test",
            args: .null,
            context: ToolContext(sessionID: "t")
        )
        guard case .object(let dict) = result else {
            Issue.record("expected object, got \(result)")
            return
        }
        #expect(dict["net"] == JSONValue.string("blocked"))
    }
}
#endif
