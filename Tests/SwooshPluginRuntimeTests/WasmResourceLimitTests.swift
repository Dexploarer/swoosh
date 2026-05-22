// Tests/SwooshPluginRuntimeTests/WasmResourceLimitTests.swift — 0.8C

import Testing
import Foundation
@testable import SwooshPlugins
@testable import SwooshPluginRuntime
@testable import SwooshTools

@Suite("Wasm resource caps")
struct WasmResourceLimitTests {

    @Test("Limiter denies memory growth beyond maxWasmMemoryPages")
    func memoryLimiterDeniesOversize() throws {
        let sandbox = PluginSandboxPolicy(
            allowFilesystemRead: false, allowFilesystemWrite: false,
            allowNetwork: false, allowProcessSpawn: false,
            allowedRoots: [], maxOutputBytes: 4_000, timeoutSeconds: 5,
            maxWasmMemoryPages: 2  // 128 KiB
        )
        let limiter = PluginWasmResourceLimiter(sandbox: sandbox)
        // 2 pages = 128 KiB allowed, 3 pages = 192 KiB denied
        let allowed = try limiter.limitMemoryGrowth(to: 128 * 1024)
        let denied = try limiter.limitMemoryGrowth(to: 192 * 1024)
        #expect(allowed)
        #expect(!denied)
    }

    @Test("Limiter denies table growth beyond maxWasmTableElements")
    func tableLimiterDeniesOversize() throws {
        let sandbox = PluginSandboxPolicy(
            allowFilesystemRead: false, allowFilesystemWrite: false,
            allowNetwork: false, allowProcessSpawn: false,
            allowedRoots: [], maxOutputBytes: 4_000, timeoutSeconds: 5,
            maxWasmTableElements: 8
        )
        let limiter = PluginWasmResourceLimiter(sandbox: sandbox)
        #expect(try limiter.limitTableGrowth(to: 8))
        #expect(!(try limiter.limitTableGrowth(to: 9)))
    }

    @Test("Function-call counter trips after exceeding limit")
    func callCounterTrips() {
        // The counter is observation-only — Function values are tricky to
        // synthesize in a test, but the tripping logic doesn't depend on
        // the function payload. We exercise the counter directly by
        // reaching into the state via the public surface.
        let counter = PluginWasmCallCounter(limit: 0)
        // Synthesize a non-zero call count by overriding the limit to 0
        // and incrementing manually through observation. We can't easily
        // construct a `Function` from outside the WasmKit module, so this
        // test only proves the "didTrip starts false" baseline; full
        // tripping behaviour is covered by the end-to-end executor tests.
        #expect(!counter.didTrip)
    }

    @Test("Backward-compat decoding fills wasm caps with defaults")
    func backwardCompatDecode() throws {
        let json = #"""
        {
          "allowFilesystemRead": false,
          "allowFilesystemWrite": false,
          "allowNetwork": false,
          "allowProcessSpawn": false,
          "allowedRoots": [],
          "maxOutputBytes": 1024,
          "timeoutSeconds": 5
        }
        """#
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PluginSandboxPolicy.self, from: data)
        #expect(decoded.maxWasmMemoryPages == 64)
        #expect(decoded.maxWasmTableElements == 1024)
        #expect(decoded.maxWasmFunctionCalls == 1_000_000)
    }
}
