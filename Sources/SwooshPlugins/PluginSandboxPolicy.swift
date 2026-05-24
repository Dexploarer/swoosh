// SwooshPlugins/PluginSandboxPolicy.swift — Sandbox capability + resource caps — 0.9A
//
// Describes what a plugin is allowed to do at runtime. The host enforces
// `allowFilesystem*` / `allowNetwork` / `allowProcessSpawn` via
// kind-specific mechanisms (sandbox-exec SBPL for executables, WASI for
// wasm). The wasm-only caps (memory pages, table elements, function-call
// budget) wire into WasmKit's `Store.resourceLimiter`.

import Foundation

public struct PluginSandboxPolicy: Codable, Sendable {
    public let allowFilesystemRead: Bool
    public let allowFilesystemWrite: Bool
    public let allowNetwork: Bool
    public let allowProcessSpawn: Bool
    public let allowedRoots: [String]
    public let maxOutputBytes: Int
    public let timeoutSeconds: Int
    /// Wasm-only: maximum linear-memory growth in 64 KiB pages. The
    /// executor wires this into `Store.resourceLimiter`. Default 64 →
    /// 4 MiB total memory cap. Ignored for non-wasm kinds.
    public let maxWasmMemoryPages: Int
    /// Wasm-only: maximum table-element growth (function references,
    /// indirect calls). Default 1024. Ignored for non-wasm kinds.
    public let maxWasmTableElements: Int
    /// Wasm-only: best-effort cap on guest function-call count. Tracked
    /// via WasmKit's `EngineInterceptor`; the interceptor can't actually
    /// abort the wasm runtime (the protocol is observation-only), so the
    /// cap acts as a tripwire — once exceeded the outer timeout takes
    /// over and the call returns with `sandboxViolation`. A "real" gas
    /// counter would require a runtime that supports execution-time
    /// budgets; WasmKit doesn't ship one today.
    public let maxWasmFunctionCalls: Int

    public static let safeDefault = PluginSandboxPolicy(
        allowFilesystemRead: false, allowFilesystemWrite: false,
        allowNetwork: false, allowProcessSpawn: false,
        allowedRoots: [], maxOutputBytes: 64_000, timeoutSeconds: 30
    )

    public init(
        allowFilesystemRead: Bool, allowFilesystemWrite: Bool,
        allowNetwork: Bool, allowProcessSpawn: Bool,
        allowedRoots: [String], maxOutputBytes: Int, timeoutSeconds: Int,
        maxWasmMemoryPages: Int = 64,
        maxWasmTableElements: Int = 1024,
        maxWasmFunctionCalls: Int = 1_000_000
    ) {
        self.allowFilesystemRead = allowFilesystemRead
        self.allowFilesystemWrite = allowFilesystemWrite
        self.allowNetwork = allowNetwork; self.allowProcessSpawn = allowProcessSpawn
        self.allowedRoots = allowedRoots; self.maxOutputBytes = maxOutputBytes
        self.timeoutSeconds = timeoutSeconds
        self.maxWasmMemoryPages = maxWasmMemoryPages
        self.maxWasmTableElements = maxWasmTableElements
        self.maxWasmFunctionCalls = maxWasmFunctionCalls
    }

    // Backward-compat decoding: manifests written before the wasm-limit
    // fields existed should still load with the safe defaults.
    private enum CodingKeys: String, CodingKey {
        case allowFilesystemRead, allowFilesystemWrite, allowNetwork, allowProcessSpawn
        case allowedRoots, maxOutputBytes, timeoutSeconds
        case maxWasmMemoryPages, maxWasmTableElements, maxWasmFunctionCalls
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.allowFilesystemRead = c.decodeOrDefault(
            Bool.self, forKey: .allowFilesystemRead, default: false
        )
        self.allowFilesystemWrite = c.decodeOrDefault(
            Bool.self, forKey: .allowFilesystemWrite, default: false
        )
        self.allowNetwork = c.decodeOrDefault(Bool.self, forKey: .allowNetwork, default: false)
        self.allowProcessSpawn = c.decodeOrDefault(
            Bool.self, forKey: .allowProcessSpawn, default: false
        )
        self.allowedRoots = c.decodeOrDefault([String].self, forKey: .allowedRoots, default: [])
        self.maxOutputBytes = c.decodeOrDefault(
            Int.self, forKey: .maxOutputBytes, default: 64_000
        )
        self.timeoutSeconds = c.decodeOrDefault(Int.self, forKey: .timeoutSeconds, default: 30)
        self.maxWasmMemoryPages = c.decodeOrDefault(
            Int.self, forKey: .maxWasmMemoryPages, default: 64
        )
        self.maxWasmTableElements = c.decodeOrDefault(
            Int.self, forKey: .maxWasmTableElements, default: 1024
        )
        self.maxWasmFunctionCalls = c.decodeOrDefault(
            Int.self, forKey: .maxWasmFunctionCalls, default: 1_000_000
        )
    }
}
