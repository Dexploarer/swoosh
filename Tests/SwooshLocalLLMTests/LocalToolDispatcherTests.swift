// Tests/SwooshLocalLLMTests/LocalToolDispatcherTests.swift
// Version: 0.9R
//
// Verifies that the local tool registry routes known names to safe
// read-only handlers, refuses unknown names when no remote forwarder is
// installed, and delegates correctly when one is.

import XCTest
@testable import SwooshLocalLLM

final class LocalToolDispatcherTests: XCTestCase {

    override func tearDown() {
        // The remoteDispatch hook is global state — reset between tests so
        // ordering doesn't matter.
        LocalToolDispatcher.setRemoteDispatch(nil)
        LocalToolDispatcher.setLocalAudit(nil)
        super.tearDown()
    }

    // MARK: - Local safe tools

    func test_dispatch_clockNow_returnsISO8601AndUnix() async throws {
        let result = try await LocalToolDispatcher.dispatch(name: "clock_now", jsonArgs: "{}")
        let json = try parse(result)
        XCTAssertNotNil(json["iso8601"] as? String, "clock_now must emit iso8601")
        XCTAssertNotNil(json["unix"] as? Int, "clock_now must emit unix epoch")
        XCTAssertNotNil(json["timezone"] as? String, "clock_now must emit timezone")
    }

    func test_dispatch_deviceInfo_returnsPlatformAndMemory() async throws {
        let result = try await LocalToolDispatcher.dispatch(name: "device_info", jsonArgs: "{}")
        let json = try parse(result)
        XCTAssertNotNil(json["platform"] as? String)
        XCTAssertNotNil(json["system_version"] as? String)
        // physical_memory_bytes comes through as UInt64 → bridged to NSNumber.
        XCTAssertNotNil(json["physical_memory_bytes"])
        XCTAssertNotNil(json["available_memory_bytes"])
    }

    func test_dispatch_appInfo_returnsBundleFields() async throws {
        let result = try await LocalToolDispatcher.dispatch(name: "app_info", jsonArgs: "{}")
        let json = try parse(result)
        XCTAssertNotNil(json["identifier"] as? String)
        XCTAssertNotNil(json["version"] as? String)
        XCTAssertNotNil(json["build"] as? String)
    }

    func test_localToolNames_matchesActualRegistry() async throws {
        // Every name advertised in `localToolNames` must actually dispatch
        // without falling through to the remote path or the error branch.
        for name in LocalToolDispatcher.localToolNames {
            let result = try await LocalToolDispatcher.dispatch(name: name, jsonArgs: "{}")
            let json = try parse(result)
            XCTAssertNil(
                json["error"] as? String,
                "Advertised local tool '\(name)' must not return an error"
            )
        }
    }

    // MARK: - Unknown names

    func test_dispatch_unknownName_returnsErrorWhenNoRemote() async throws {
        let result = try await LocalToolDispatcher.dispatch(name: "delete_everything", jsonArgs: "{}")
        let json = try parse(result)
        XCTAssertNotNil(
            json["error"] as? String,
            "Unknown tool with no remote forwarder MUST return error, never silently succeed"
        )
    }

    func test_dispatch_unknownName_delegatesToRemoteWhenInstalled() async throws {
        let expectation = self.expectation(description: "remote dispatch called")
        let captured = CapturedCall()
        LocalToolDispatcher.setRemoteDispatch { name, args in
            await captured.set(name: name, args: args)
            expectation.fulfill()
            return "{\"forwarded\":true}"
        }

        let result = try await LocalToolDispatcher.dispatch(
            name: "fs_read",
            jsonArgs: "{\"path\":\"/tmp/x\"}"
        )

        await fulfillment(of: [expectation], timeout: 1.0)
        let name = await captured.name
        let args = await captured.args
        XCTAssertEqual(name, "fs_read")
        XCTAssertEqual(args, "{\"path\":\"/tmp/x\"}")
        XCTAssertTrue(result.contains("forwarded"))
    }

    func test_dispatch_localTools_bypassRemoteForwarder() async throws {
        // Even when a remote dispatcher is installed, the local safe tools
        // must answer locally — otherwise an offline `clock_now` would
        // try to reach the (offline) daemon and fail.
        let counter = Counter()
        LocalToolDispatcher.setRemoteDispatch { _, _ in
            await counter.increment()
            return "{}"
        }

        for name in LocalToolDispatcher.localToolNames {
            _ = try await LocalToolDispatcher.dispatch(name: name, jsonArgs: "{}")
        }

        let calls = await counter.value
        XCTAssertEqual(calls, 0, "Local safe tools must answer locally even when a remote dispatcher is installed")
    }

    // MARK: - Local audit hook

    func test_localAudit_calledForEveryLocalToolWithName() async throws {
        // The audit hook fires before every local tool execution so the
        // host can log the on-device call surface even when the daemon
        // is unreachable. Unknown names skip the hook (they're forwarded
        // to the remote dispatcher instead).
        let calls = NameCapture()
        LocalToolDispatcher.setLocalAudit { name, _ in
            Task { await calls.append(name) }
        }

        for name in LocalToolDispatcher.localToolNames {
            _ = try await LocalToolDispatcher.dispatch(name: name, jsonArgs: "{}")
        }
        _ = try await LocalToolDispatcher.dispatch(name: "delete_everything", jsonArgs: "{}")

        // Give the audit-hook Task a tick to enqueue, then check.
        try await Task.sleep(nanoseconds: 10_000_000)
        let captured = Set(await calls.values)
        XCTAssertEqual(
            captured, LocalToolDispatcher.localToolNames,
            "Audit hook must fire for every local-set name and only for those"
        )
    }

    // MARK: - Helpers

    private func parse(_ jsonString: String) throws -> [String: Any] {
        let data = Data(jsonString.utf8)
        let any = try JSONSerialization.jsonObject(with: data)
        guard let dict = any as? [String: Any] else {
            XCTFail("Expected JSON object, got: \(jsonString)")
            return [:]
        }
        return dict
    }
}

/// Captures the (name, args) pair from a sendable closure.
private actor CapturedCall {
    var name: String?
    var args: String?
    func set(name: String, args: String) {
        self.name = name
        self.args = args
    }
}

/// Async-safe counter for verifying call counts from sendable closures.
private actor Counter {
    var value: Int = 0
    func increment() { value += 1 }
}

/// Async-safe ordered collector for verifying which tool names the
/// audit hook fires on.
private actor NameCapture {
    var values: [String] = []
    func append(_ name: String) { values.append(name) }
}
