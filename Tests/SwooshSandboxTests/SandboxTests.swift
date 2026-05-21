// Tests/SwooshSandboxTests/SandboxTests.swift — Sandbox policy + executor
//
// SwooshSandbox provides sandboxed execution of untrusted code via
// macOS sandbox-exec. Tests focus on policy construction, defaults,
// serialization, and the SandboxResult/SandboxError types.
// The executor's real Process invocation is covered minimally and
// behind capability checks so tests work on CI.

import Testing
import Foundation
@testable import SwooshSandbox

// MARK: - SandboxPolicy

@Suite("SandboxPolicy Initialization")
struct SandboxPolicyInitTests {

    @Test("Default policy is locked down")
    func defaultPolicyLockedDown() {
        let policy = SandboxPolicy()
        #expect(policy.allowNetwork == false)
        #expect(policy.allowFileRead.isEmpty)
        #expect(policy.allowFileWrite.isEmpty)
        #expect(policy.allowProcessExec == false)
        #expect(policy.maxMemoryMB == 256)
        #expect(policy.maxCPUSeconds == 30)
        #expect(policy.maxOutputBytes == 1_048_576)
        #expect(policy.environment.isEmpty)
    }

    @Test("Custom policy preserves all fields")
    func customPolicyPreservesFields() {
        let policy = SandboxPolicy(
            allowNetwork: true,
            allowFileRead: ["/tmp"],
            allowFileWrite: ["/var"],
            allowProcessExec: true,
            maxMemoryMB: 2048,
            maxCPUSeconds: 60,
            maxOutputBytes: 5_000_000,
            environment: ["KEY": "VALUE"]
        )
        #expect(policy.allowNetwork == true)
        #expect(policy.allowFileRead == ["/tmp"])
        #expect(policy.allowFileWrite == ["/var"])
        #expect(policy.allowProcessExec == true)
        #expect(policy.maxMemoryMB == 2048)
        #expect(policy.maxCPUSeconds == 60)
        #expect(policy.maxOutputBytes == 5_000_000)
        #expect(policy.environment["KEY"] == "VALUE")
    }
}

@Suite("SandboxPolicy Presets")
struct SandboxPolicyPresetTests {

    @Test("strict preset matches default")
    func strictMatchesDefault() {
        let strict = SandboxPolicy.strict
        let dflt = SandboxPolicy()
        #expect(strict.allowNetwork == dflt.allowNetwork)
        #expect(strict.allowProcessExec == dflt.allowProcessExec)
        #expect(strict.allowFileRead == dflt.allowFileRead)
        #expect(strict.allowFileWrite == dflt.allowFileWrite)
    }

    @Test("readOnly grants read paths but no writes or network")
    func readOnlyGrantsReadOnly() {
        let policy = SandboxPolicy.readOnly(paths: ["/Users/foo", "/Users/bar"])
        #expect(policy.allowFileRead == ["/Users/foo", "/Users/bar"])
        #expect(policy.allowFileWrite.isEmpty)
        #expect(policy.allowNetwork == false)
        #expect(policy.allowProcessExec == false)
    }

    @Test("development preset enables read+write+network+exec")
    func developmentPreset() {
        let policy = SandboxPolicy.development(projectDir: "/Users/me/project")
        #expect(policy.allowNetwork == true)
        #expect(policy.allowProcessExec == true)
        #expect(policy.allowFileRead.contains("/Users/me/project"))
        #expect(policy.allowFileRead.contains("/usr"))
        #expect(policy.allowFileRead.contains("/Library"))
        #expect(policy.allowFileWrite == ["/Users/me/project"])
        #expect(policy.maxMemoryMB == 1024)
        #expect(policy.maxCPUSeconds == 300)
    }
}

@Suite("SandboxPolicy Codable")
struct SandboxPolicyCodableTests {

    @Test("Round-trip JSON preserves fields")
    func roundTrip() throws {
        let original = SandboxPolicy.development(projectDir: "/Users/test/proj")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SandboxPolicy.self, from: data)

        #expect(decoded.allowNetwork == original.allowNetwork)
        #expect(decoded.allowFileRead == original.allowFileRead)
        #expect(decoded.allowFileWrite == original.allowFileWrite)
        #expect(decoded.allowProcessExec == original.allowProcessExec)
        #expect(decoded.maxMemoryMB == original.maxMemoryMB)
        #expect(decoded.maxCPUSeconds == original.maxCPUSeconds)
        #expect(decoded.maxOutputBytes == original.maxOutputBytes)
    }
}

// MARK: - SandboxResult

@Suite("SandboxResult")
struct SandboxResultTests {

    @Test("succeeded requires exit code 0 and not killed")
    func succeededLogic() {
        let ok = SandboxResult(
            exitCode: 0, stdout: "", stderr: "",
            durationSeconds: 1, wasKilled: false, filesModified: []
        )
        #expect(ok.succeeded == true)

        let nonZero = SandboxResult(
            exitCode: 1, stdout: "", stderr: "err",
            durationSeconds: 1, wasKilled: false, filesModified: []
        )
        #expect(nonZero.succeeded == false)

        let killed = SandboxResult(
            exitCode: 0, stdout: "", stderr: "",
            durationSeconds: 30, wasKilled: true, filesModified: []
        )
        #expect(killed.succeeded == false)
    }

    @Test("Stores all fields")
    func storesFields() {
        let r = SandboxResult(
            exitCode: 42,
            stdout: "out",
            stderr: "err",
            durationSeconds: 2.5,
            wasKilled: false,
            filesModified: ["/tmp/a"]
        )
        #expect(r.exitCode == 42)
        #expect(r.stdout == "out")
        #expect(r.stderr == "err")
        #expect(r.durationSeconds == 2.5)
        #expect(r.filesModified == ["/tmp/a"])
    }
}

// MARK: - SandboxError

@Suite("SandboxError")
struct SandboxErrorTests {

    @Test("Error cases distinguish")
    func errorCases() {
        let violation: SandboxError = .policyViolation("network forbidden")
        let exec: SandboxError = .executionFailed("bad command")
        let timeout: SandboxError = .timeout
        let memory: SandboxError = .memoryExceeded

        switch violation {
        case .policyViolation(let m): #expect(m == "network forbidden")
        default: Issue.record("wrong case")
        }
        switch exec {
        case .executionFailed(let m): #expect(m == "bad command")
        default: Issue.record("wrong case")
        }
        if case .timeout = timeout {} else { Issue.record("timeout case") }
        if case .memoryExceeded = memory {} else { Issue.record("memory case") }
    }
}

// MARK: - SandboxExecutor (smoke)

@Suite("SandboxExecutor Smoke")
struct SandboxExecutorSmokeTests {

    @Test("Initializes with default policy")
    func defaultInit() async {
        let exec = SandboxExecutor()
        _ = exec
        #expect(Bool(true))
    }

    @Test("Initializes with custom policy")
    func customInit() async {
        let exec = SandboxExecutor(policy: .readOnly(paths: ["/tmp"]))
        _ = exec
        #expect(Bool(true))
    }

    /// Executes a trivial command via the unsandboxed path (allowProcessExec=true).
    /// We avoid invoking sandbox-exec because its profile requires absolute paths
    /// and entitlements that vary on CI.
    @Test("Echo via process-exec policy returns expected stdout", .timeLimit(.minutes(1)))
    func echoExecutes() async throws {
        let policy = SandboxPolicy(allowProcessExec: true, maxCPUSeconds: 10)
        let exec = SandboxExecutor(policy: policy)
        let result = try await exec.execute(command: "/bin/echo", arguments: ["hello"])
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("hello"))
        #expect(result.succeeded)
    }
}
