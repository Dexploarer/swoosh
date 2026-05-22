// SwooshPluginRuntime/ExecutablePluginExecutor.swift — 0.8B Executable Kind
//
// Spawns a fresh subprocess per call from `manifest.entrypoint.executable`,
// then talks single-shot JSON-RPC over stdio:
//
//   stdin  ← {"tool": "<name>", "args": {...}}
//   stdout → {"ok": true, "output": <JSONValue>}
//        or → {"ok": false, "error": "<message>"}
//
// The "one process per call" shape is deliberate. It keeps each tool call
// independent — no shared state, no leaked file descriptors, easy to kill
// on timeout. The shell of long-running plugin processes is out of scope
// for this pass; if a plugin needs persistence it can write to its plugin
// dir between calls.
//
// Sandbox enforcement:
//   • `sandbox.timeoutSeconds` → a sibling task terminates the process if
//     it hasn't exited; SIGTERM, then the call throws `sandboxViolation`.
//   • `sandbox.maxOutputBytes` → stdout/stderr are capped at this many
//     bytes; if the cap is hit the process is terminated and the call
//     throws `sandboxViolation`.
//   • Working directory is forced to the plugin directory so relative
//     paths inside the plugin work but `..` escapes don't help (no chroot,
//     just convention).
//   • Environment is scrubbed: only `PATH`, `HOME`, and any `SWOOSH_PLUGIN_*`
//     vars are forwarded. Secrets in the daemon's env can't leak.
//
// What this *doesn't* do (documented for honesty, not handwave):
//   • No network firewalling. macOS plugin processes can still open
//     sockets. Disabling network requires `sandbox-exec` or App Sandbox
//     entitlements — a later pass.
//   • No filesystem confinement beyond the cwd convention. A determined
//     plugin can still read $HOME. Filesystem confinement also needs
//     sandbox-exec.

import Foundation
import SwooshPlugins
import SwooshTools

public struct ExecutablePluginExecutor: PluginExecutor {
    public let kind: PluginKind = .executable
    public let pluginsRoot: URL

    public init(pluginsRoot: URL) {
        self.pluginsRoot = pluginsRoot.standardizedFileURL
    }

    public func call(
        manifest: PluginManifest,
        toolName: String,
        args: JSONValue,
        context: ToolContext
    ) async throws -> JSONValue {
        guard case .executable(let path, let arguments) = manifest.entrypoint else {
            throw PluginError.missingEntrypoint(
                pluginID: manifest.id,
                detail: "manifest kind is `executable` but entrypoint is \(manifest.entrypoint)"
            )
        }

        let pluginDir = pluginsRoot.appendingPathComponent(manifest.id, isDirectory: true).standardizedFileURL
        let resolvedExe = resolveExecutable(path: path, pluginDir: pluginDir)
        guard FileManager.default.isExecutableFile(atPath: resolvedExe.path) else {
            throw PluginError.missingEntrypoint(
                pluginID: manifest.id,
                detail: "executable not found or not executable: \(resolvedExe.path)"
            )
        }

        let request: JSONValue = .object([
            "tool": .string(toolName),
            "args": args,
        ])
        let requestData = try JSONEncoder().encode(request)

        // Wrap the spawn under macOS sandbox-exec when available — this
        // is defense in depth on top of the env scrub / cwd convention.
        // Disable with SWOOSH_PLUGIN_DISABLE_SBPL=1 for debugging.
        let (wrappedExe, wrappedArgs): (URL, [String]) = {
            #if os(macOS)
            let disabled = ProcessInfo.processInfo.environment["SWOOSH_PLUGIN_DISABLE_SBPL"] == "1"
            guard !disabled, SBPLProfileBuilder.isAvailable else {
                return (resolvedExe, arguments)
            }
            let profile = SBPLProfileBuilder.profile(
                pluginDir: pluginDir,
                allowNetwork: manifest.sandbox.allowNetwork,
                allowFilesystemWrite: manifest.sandbox.allowFilesystemWrite,
                allowedRoots: manifest.sandbox.allowedRoots
            )
            return (
                URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
                ["-p", profile, resolvedExe.path] + arguments
            )
            #else
            return (resolvedExe, arguments)
            #endif
        }()

        return try await Self.runSubprocess(
            executable: wrappedExe,
            arguments: wrappedArgs,
            workingDir: pluginDir,
            environment: Self.sandboxedEnv(),
            stdin: requestData,
            timeoutSeconds: max(1, manifest.sandbox.timeoutSeconds),
            maxOutputBytes: max(256, manifest.sandbox.maxOutputBytes),
            pluginID: manifest.id
        )
    }

    private func resolveExecutable(path: String, pluginDir: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return pluginDir.appendingPathComponent(path).standardizedFileURL
    }

    static func sandboxedEnv() -> [String: String] {
        let env = ProcessInfo.processInfo.environment
        var out: [String: String] = [:]
        if let p = env["PATH"] { out["PATH"] = p }
        if let h = env["HOME"] { out["HOME"] = h }
        for (k, v) in env where k.hasPrefix("SWOOSH_PLUGIN_") {
            out[k] = v
        }
        return out
    }

    /// Run the subprocess and return the parsed response payload. Throws on
    /// timeout, output overflow, non-zero exit (when the plugin didn't
    /// emit a structured error), or malformed output.
    static func runSubprocess(
        executable: URL,
        arguments: [String],
        workingDir: URL,
        environment: [String: String],
        stdin: Data,
        timeoutSeconds: Int,
        maxOutputBytes: Int,
        pluginID: String
    ) async throws -> JSONValue {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDir
        process.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw PluginError.missingEntrypoint(
                pluginID: pluginID,
                detail: "spawn failed: \(error.localizedDescription)"
            )
        }

        // Push the request payload and close the write end so the plugin
        // reads EOF on stdin.
        do {
            try stdinPipe.fileHandleForWriting.write(contentsOf: stdin)
            try stdinPipe.fileHandleForWriting.close()
        } catch {
            process.terminate()
            throw PluginError.sandboxViolation("stdin write to plugin \(pluginID) failed: \(error.localizedDescription)")
        }

        // Timeout watchdog. Cancelled below if the process exits cleanly.
        let timeoutTask = Task<Bool, Never> {
            do {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
            } catch {
                return false
            }
            if process.isRunning {
                process.terminate()
                return true
            }
            return false
        }

        // waitUntilExit() blocks the current cooperative thread. Run it on
        // a detached priority so we don't pin the global executor. Returns
        // the captured stdout/stderr + exit status.
        let captured = await withCheckedContinuation { (continuation: CheckedContinuation<(stdout: Data, stderr: Data, exit: Int32, hitCap: Bool), Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var stdoutData = Data()
                var stderrData = Data()
                var hitCap = false

                let stdoutHandle = stdoutPipe.fileHandleForReading
                let stderrHandle = stderrPipe.fileHandleForReading

                // Read in chunks until EOF, enforcing the cap.
                while true {
                    let chunk = stdoutHandle.availableData
                    if chunk.isEmpty { break }
                    if stdoutData.count + chunk.count > maxOutputBytes {
                        let remaining = max(0, maxOutputBytes - stdoutData.count)
                        stdoutData.append(chunk.prefix(remaining))
                        hitCap = true
                        if process.isRunning { process.terminate() }
                        break
                    }
                    stdoutData.append(chunk)
                }
                stderrData = (try? stderrHandle.readToEnd()) ?? Data()
                if stderrData.count > maxOutputBytes {
                    stderrData = stderrData.prefix(maxOutputBytes)
                }
                process.waitUntilExit()
                continuation.resume(returning: (stdoutData, stderrData, process.terminationStatus, hitCap))
            }
        }

        let timedOut = await timeoutTask.value
        timeoutTask.cancel()

        if timedOut {
            throw PluginError.sandboxViolation("plugin \(pluginID) exceeded timeout of \(timeoutSeconds)s")
        }
        if captured.hitCap {
            throw PluginError.sandboxViolation("plugin \(pluginID) exceeded maxOutputBytes (\(maxOutputBytes))")
        }

        // Plugins talk JSON on stdout. A non-zero exit code without a
        // structured `{"ok": false, "error": "..."}` on stdout is treated
        // as a sandbox violation — plugins must always emit a parseable
        // response even when they fail.
        guard !captured.stdout.isEmpty else {
            let stderr = String(data: captured.stderr, encoding: .utf8) ?? ""
            throw PluginError.sandboxViolation(
                "plugin \(pluginID) exited \(captured.exit) with empty stdout. stderr: \(stderr.prefix(500))"
            )
        }

        let decoder = JSONDecoder()
        let response: ExecutableResponse
        do {
            response = try decoder.decode(ExecutableResponse.self, from: captured.stdout)
        } catch {
            throw PluginError.sandboxViolation(
                "plugin \(pluginID) returned malformed JSON: \(error.localizedDescription)"
            )
        }

        if response.ok {
            return response.output ?? .null
        }
        throw PluginError.toolFailed(
            response.error ?? "plugin \(pluginID) reported ok=false with no error detail"
        )
    }
}

/// Wire format the executable plugin must emit on stdout.
struct ExecutableResponse: Codable, Sendable {
    let ok: Bool
    let output: JSONValue?
    let error: String?
}
