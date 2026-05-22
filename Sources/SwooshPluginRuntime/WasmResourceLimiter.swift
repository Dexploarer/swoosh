// SwooshPluginRuntime/WasmResourceLimiter.swift — 0.8C Wasm Resource Caps
//
// Wraps WasmKit's `ResourceLimiter` protocol with the per-plugin sandbox
// values declared in the manifest. The limiter is set on `Store` after
// construction; WasmKit then calls into it when the wasm module tries to
// grow its linear memory or function tables. Returning `false` from the
// limiter denies the growth — the wasm `memory.grow` instruction sees the
// failure and reports it to the guest, which typically traps.

import Foundation
import SwooshPlugins
import WasmKit

/// Per-call resource limiter for wasm plugins. Stateless beyond the
/// configured caps, so safe to share across stores in principle — but
/// we construct a fresh one per call to keep the limiter and store
/// lifetimes tied together.
public struct PluginWasmResourceLimiter: ResourceLimiter, Sendable {
    public let maxMemoryBytes: Int
    public let maxTableElements: Int

    public init(sandbox: PluginSandboxPolicy) {
        // WasmKit memories grow in 64 KiB pages. The limiter receives a
        // byte count, so pre-multiply once.
        let pageBytes = 64 * 1024
        self.maxMemoryBytes = max(pageBytes, sandbox.maxWasmMemoryPages * pageBytes)
        self.maxTableElements = max(0, sandbox.maxWasmTableElements)
    }

    public func limitMemoryGrowth(to desired: Int) throws -> Bool {
        desired <= maxMemoryBytes
    }

    public func limitTableGrowth(to desired: Int) throws -> Bool {
        desired <= maxTableElements
    }
}

/// Function-call counter. WasmKit's `EngineInterceptor` protocol is
/// observational only — the methods don't throw, so we can't actually
/// abort wasm execution from here. The counter exists so the executor can
/// detect "this plugin made more than N function calls and the wall-clock
/// timeout should kick in soon" and surface a precise sandbox violation
/// instead of a generic timeout.
public final class PluginWasmCallCounter: EngineInterceptor, @unchecked Sendable {
    public let limit: Int
    private let lock = NSLock()
    private var calls: Int = 0
    private var trippedAt: Date?

    public init(limit: Int) {
        self.limit = limit
    }

    public func onEnterFunction(_ function: Function) {
        lock.lock(); defer { lock.unlock() }
        calls &+= 1
        if calls > limit, trippedAt == nil {
            trippedAt = Date()
        }
    }

    public func onExitFunction(_ function: Function) {}

    /// `true` iff the wasm exceeded `limit` function calls. The executor
    /// promotes this from "outer timeout fired" → "sandbox violation:
    /// function-call cap" so users get a clearer error message.
    public var didTrip: Bool {
        lock.lock(); defer { lock.unlock() }
        return trippedAt != nil
    }

    public var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return calls
    }
}
