// SwooshPluginRuntime/WasmPluginExecutor.swift — 0.8B Wasm Kind
//
// Embeds a WebAssembly module via WasmKit. The plugin file is whatever the
// manifest's `entrypoint.wasm(path:)` points at; if its extension is
// `.wat`, the file is compiled to a wasm binary at load time via WAT's
// `wat2wasm()` so plugin authors can ship human-readable source. Compiled
// `.wasm` files are also supported and skipped through that conversion
// step.
//
// ABI (linear-memory, no WASI):
//   The module is expected to export a function whose name matches the
//   plugin tool's *bare* name (the manifest's `name`, not the
//   `plugin.<name>` form). The function signature is tool-specific. The
//   executor knows how to marshal a small set of demo signatures — see
//   `marshalCall` — and rejects unknown signatures with
//   `PluginError.toolNotRegistered`.
//
// What this *doesn't* do (deliberately scoped for Phase 3):
//   • No WASI (no stdin/stdout/filesystem bridges). Adding WASI is a
//     follow-on — for now the demo proves the runtime is wired and the
//     trust boundary holds.
//   • No execution-time guard. Wasm runs synchronously inside a detached
//     task; if the plugin loops forever the task leaks. The host call is
//     still bounded by `sandbox.timeoutSeconds`, after which the call
//     returns with `sandboxViolation` and the leaked task is allowed to
//     finish in the background (its result is discarded). A production
//     pass would use WasmKit's resource limiter to enforce gas counts.

import Foundation
import SwooshPlugins
import SwooshTools
// Access `Store.resourceLimiter`. The field is `@_spi(Fuzzing)` upstream
// with a comment marking it as a candidate for promotion to public API;
// using the SPI here is the cleanest way to plumb memory/table caps in
// without forking WasmKit. If upstream drops the SPI guard this import
// becomes a no-op.
@_spi(Fuzzing) import WasmKit
import WAT
import WasmKitWASI
import SystemPackage

public struct WasmPluginExecutor: PluginExecutor {
    public let kind: PluginKind = .wasm
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
        let path: String
        let useWASI: Bool
        switch manifest.entrypoint {
        case .wasm(let p):
            path = p; useWASI = false
        case .wasiWasm(let p):
            path = p; useWASI = true
        default:
            throw PluginError.missingEntrypoint(
                pluginID: manifest.id,
                detail: "manifest kind is `wasm` but entrypoint is \(manifest.entrypoint)"
            )
        }
        let pluginDir = pluginsRoot.appendingPathComponent(manifest.id, isDirectory: true)
        let moduleURL = pluginDir.appendingPathComponent(path).standardizedFileURL
        guard FileManager.default.fileExists(atPath: moduleURL.path) else {
            throw PluginError.missingEntrypoint(
                pluginID: manifest.id,
                detail: "wasm module not found: \(moduleURL.path)"
            )
        }

        let bytes: [UInt8]
        do {
            let data = try Data(contentsOf: moduleURL)
            if moduleURL.pathExtension.lowercased() == "wat" {
                let text = String(decoding: data, as: UTF8.self)
                bytes = try wat2wasm(text)
            } else {
                bytes = Array(data)
            }
        } catch {
            throw PluginError.sandboxViolation(
                "wasm plugin \(manifest.id): failed to load module — \(error.localizedDescription)"
            )
        }

        let timeoutSeconds = max(1, manifest.sandbox.timeoutSeconds)
        let pluginID = manifest.id
        let sandbox = manifest.sandbox
        let workTask = Task.detached(priority: .userInitiated) { () -> Result<JSONValue, Error> in
            do {
                let value: JSONValue
                if useWASI {
                    value = try Self.runWASIModule(
                        bytes: bytes, toolName: toolName, args: args,
                        pluginID: pluginID, sandbox: sandbox
                    )
                } else {
                    value = try Self.runModule(
                        bytes: bytes, toolName: toolName, args: args,
                        pluginID: pluginID, sandbox: sandbox
                    )
                }
                return .success(value)
            } catch {
                return .failure(error)
            }
        }

        // Race the work against the timeout.
        let raceResult: WasmRaceResult = await withTaskGroup(of: WasmRaceResult.self) { group in
            group.addTask { .work(await workTask.value) }
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
                    return .timeout(!Task.isCancelled)
                } catch {
                    return .timeout(false)
                }
            }
            // First settled wins.
            let first = await group.next() ?? .timeout(false)
            group.cancelAll()
            return first
        }

        switch raceResult {
        case .work(let result):
            switch result {
            case .success(let value): return value
            case .failure(let error): throw error
            }
        case .timeout(let fired):
            workTask.cancel()
            if fired {
                throw PluginError.sandboxViolation(
                    "wasm plugin \(manifest.id) exceeded timeout of \(timeoutSeconds)s"
                )
            }
            // Timeout task returned false (cancelled by work completing
            // first) — read the work result. Should not happen given the
            // group semantics above, but cover the case for completeness.
            switch await workTask.value {
            case .success(let value): return value
            case .failure(let error): throw error
            }
        }
    }

    // MARK: - Module execution

    private static func runModule(
        bytes: [UInt8], toolName: String,
        args: JSONValue, pluginID: String,
        sandbox: PluginSandboxPolicy
    ) throws -> JSONValue {
        let counter = PluginWasmCallCounter(limit: sandbox.maxWasmFunctionCalls)
        let engine = Engine(interceptor: counter)
        let store = Store(engine: engine)
        store.resourceLimiter = PluginWasmResourceLimiter(sandbox: sandbox)
        let module = try parseWasm(bytes: bytes)
        // The demo modules don't import anything (no WASI), so an empty
        // import set suffices.
        let imports = Imports()
        let instance = try module.instantiate(store: store, imports: imports)
        let value = try marshalCall(
            instance: instance, store: store,
            toolName: toolName, args: args, pluginID: pluginID
        )
        if counter.didTrip {
            throw PluginError.sandboxViolation(
                "wasm plugin \(pluginID) exceeded function-call cap (\(counter.limit))"
            )
        }
        return value
    }

    /// WASI ABI runner. argv carries `[pluginID, toolName, argsJSON]`; the
    /// module reads stdin (currently empty), writes its response JSON to
    /// stdout, and exits. Non-zero exit codes become `PluginError.toolFailed`.
    /// No preopens, no environment — the sandbox is whatever WasmKit gives
    /// us by default plus the empty world we hand it.
    private static func runWASIModule(
        bytes: [UInt8], toolName: String,
        args: JSONValue, pluginID: String,
        sandbox: PluginSandboxPolicy
    ) throws -> JSONValue {
        let argsJSON: String = {
            guard let data = try? JSONEncoder().encode(args),
                  let str = String(data: data, encoding: .utf8) else {
                return "{}"
            }
            return str
        }()

        // Pipes: stdin (host writes "", wasm reads); stdout (wasm writes,
        // host reads). We open OS-level pipes via Foundation.Pipe and
        // forward the FDs into WasmKitWASI. The bridge captures raw FDs
        // via `FileDescriptor(rawValue:)` *without* taking ownership, so
        // every handle has to be closed explicitly here — six per call,
        // and the host runs out of FDs after a couple hundred calls if
        // we leak any.
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        // Close the write end of stdin immediately — there's no payload
        // beyond argv in this ABI.
        try? stdinPipe.fileHandleForWriting.close()
        defer {
            try? stdinPipe.fileHandleForReading.close()
            try? stdoutPipe.fileHandleForReading.close()
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForWriting.close()
        }

        let wasi = try WASIBridgeToHost(
            args: [pluginID, toolName, argsJSON],
            environment: [:],
            preopens: [WASIBridgeToHost.Preopen](),
            stdin: FileDescriptor(rawValue: stdinPipe.fileHandleForReading.fileDescriptor),
            stdout: FileDescriptor(rawValue: stdoutPipe.fileHandleForWriting.fileDescriptor),
            stderr: FileDescriptor(rawValue: stderrPipe.fileHandleForWriting.fileDescriptor)
        )
        defer { try? wasi.close() }

        let counter = PluginWasmCallCounter(limit: sandbox.maxWasmFunctionCalls)
        let engine = Engine(interceptor: counter)
        let store = Store(engine: engine)
        store.resourceLimiter = PluginWasmResourceLimiter(sandbox: sandbox)
        var imports = Imports()
        wasi.link(to: &imports, store: store)
        let module = try parseWasm(bytes: bytes)
        let instance = try module.instantiate(store: store, imports: imports)
        let exit = try wasi.start(instance)
        if counter.didTrip {
            throw PluginError.sandboxViolation(
                "WASI plugin \(pluginID) exceeded function-call cap (\(counter.limit))"
            )
        }
        // Close the write ends BEFORE reading so the readDataToEndOfFile
        // call below doesn't block. The defer above handles the rest.
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        if exit != 0 {
            let detail = String(data: stderrData, encoding: .utf8) ?? ""
            throw PluginError.toolFailed(
                "WASI plugin \(pluginID) exited \(exit). stderr: \(detail.prefix(500))"
            )
        }

        guard !stdoutData.isEmpty else {
            return .object(["pluginID": .string(pluginID), "text": .string("")])
        }
        // Try JSON; fall back to wrapping raw text.
        if let value = try? JSONDecoder().decode(JSONValue.self, from: stdoutData) {
            return value
        }
        let text = String(data: stdoutData, encoding: .utf8) ?? ""
        return .object(["pluginID": .string(pluginID), "text": .string(text)])
    }

    /// Map a manifest tool name + args to a wasm export call. Phase 3
    /// understands one demo signature; future tools will extend this
    /// dispatch.
    ///
    /// Tool-name → wasm-export convention: the final dot-separated
    /// segment is the export name. So `wasm.add` looks up the export
    /// `add`; `myplugin.compute_thing` looks up `compute_thing`. The
    /// prefix is purely organisational and ignored by the executor —
    /// authors use it to namespace their tools by plugin/family.
    private static func marshalCall(
        instance: Instance, store: Store,
        toolName: String, args: JSONValue, pluginID: String
    ) throws -> JSONValue {
        let exportName = toolName.split(separator: ".").last.map(String.init) ?? toolName
        guard let function = instance.exports[function: exportName] else {
            throw PluginError.toolNotRegistered(
                "wasm plugin \(pluginID): no export `\(exportName)` for tool `\(toolName)`"
            )
        }

        switch toolName {
        case "wasm.add":
            // Demo signature: (i32, i32) -> i32. Args: { "a": int, "b": int }.
            let (a, b) = try Self.intPair(args, pluginID: pluginID)
            let results = try function.invoke([.i32(UInt32(bitPattern: Int32(a))), .i32(UInt32(bitPattern: Int32(b)))])
            guard let first = results.first, case .i32(let raw) = first else {
                throw PluginError.sandboxViolation(
                    "wasm plugin \(pluginID): tool `\(toolName)` returned no i32 result"
                )
            }
            let sum = Int(Int32(bitPattern: raw))
            return .object(["sum": .int(sum), "pluginID": .string(pluginID)])
        default:
            throw PluginError.toolNotRegistered(
                "wasm plugin \(pluginID): no marshalling for tool `\(toolName)` — Phase 3 demo only supports `wasm.add`"
            )
        }
    }

    private static func intPair(_ value: JSONValue, pluginID: String) throws -> (Int, Int) {
        guard case .object(let dict) = value else {
            throw PluginError.sandboxViolation(
                "wasm plugin \(pluginID): expected object args with keys `a` and `b`"
            )
        }
        let a = try Self.int(dict["a"], key: "a", pluginID: pluginID)
        let b = try Self.int(dict["b"], key: "b", pluginID: pluginID)
        return (a, b)
    }

    private static func int(_ value: JSONValue?, key: String, pluginID: String) throws -> Int {
        switch value {
        case .int(let n): return n
        case .double(let d): return Int(d)
        case .string(let s):
            if let n = Int(s) { return n }
            throw PluginError.sandboxViolation(
                "wasm plugin \(pluginID): arg `\(key)` is a non-numeric string: \(s)"
            )
        default:
            throw PluginError.sandboxViolation(
                "wasm plugin \(pluginID): arg `\(key)` missing or not numeric"
            )
        }
    }
}

private enum WasmRaceResult: Sendable {
    case work(Result<JSONValue, Error>)
    case timeout(Bool)
}
