// Tests/SwooshDevToolsTests/DevToolsTests.swift — 0.4C Tests
//
// Path safety, sensitive file blocking, process runner safety,
// diagnostic parsing, and approved root enforcement.

import Testing
import Foundation
@testable import SwooshFiles
@testable import SwooshProcess
@testable import SwooshTools

// ═══════════════════════════════════════════════════════════════
// MARK: - Test fixtures
// ═══════════════════════════════════════════════════════════════

func makeTestRoot(
    path: String = "/tmp/swoosh-test-root",
    read: Bool = true,
    write: Bool = true
) -> ApprovedRoot {
    ApprovedRoot(
        id: "test-root",
        displayName: "Test Root",
        absolutePath: path,
        allowedRead: read,
        allowedWrite: write
    )
}

// ═══════════════════════════════════════════════════════════════
// MARK: - SafePathResolver Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Safe Path Resolver")
struct SafePathResolverTests {
    let resolver = SafePathResolver()
    let root = makeTestRoot(path: "/Users/test/Projects/Swoosh")

    @Test("Absolute path is rejected")
    func absolutePathRejected() {
        #expect(throws: FileAccessError.self) {
            _ = try resolver.resolve(root: root, relativePath: "/etc/passwd")
        }
    }

    @Test("Parent traversal is rejected")
    func parentTraversalRejected() {
        #expect(throws: FileAccessError.self) {
            _ = try resolver.resolve(root: root, relativePath: "../../../etc/passwd")
        }
    }

    @Test("Double-dot in middle rejected")
    func doubleDotMiddleRejected() {
        #expect(throws: FileAccessError.self) {
            _ = try resolver.resolve(root: root, relativePath: "src/../../../etc/passwd")
        }
    }

    @Test("Valid relative path resolves correctly")
    func validRelativePathResolves() throws {
        let url = try resolver.resolve(root: root, relativePath: "Sources/SwooshCore/AgentKernel.swift")
        #expect(url.path.contains("Sources/SwooshCore/AgentKernel.swift"))
        #expect(url.path.hasPrefix("/Users/test/Projects/Swoosh"))
    }

    @Test("Empty relative path resolves to root")
    func emptyRelativePathIsRoot() throws {
        let url = try resolver.resolve(root: root, relativePath: "")
        #expect(url.path == "/Users/test/Projects/Swoosh")
    }

    @Test("Write denied for read-only root")
    func writeDeniedForReadOnlyRoot() {
        let readOnlyRoot = makeTestRoot(path: "/tmp/test", write: false)
        #expect(throws: FileAccessError.self) {
            try resolver.validateAccess(root: readOnlyRoot, write: true)
        }
    }

    @Test("Read denied when read not allowed")
    func readDenied() {
        let noReadRoot = makeTestRoot(path: "/tmp/test", read: false)
        #expect(throws: FileAccessError.self) {
            try resolver.validateAccess(root: noReadRoot, write: false)
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Sensitive File Policy Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Sensitive File Policy")
struct SensitiveFilePolicyTests {
    let policy = SensitiveFilePolicy()

    @Test(".env is blocked")
    func dotEnvBlocked() {
        #expect(policy.shouldBlock(path: ".env") == true)
        #expect(policy.shouldBlock(path: "config/.env.local") == true)
        #expect(policy.shouldBlock(path: ".env.production") == true)
    }

    @Test("SSH private key is blocked")
    func sshKeyBlocked() {
        #expect(policy.shouldBlock(path: "id_rsa") == true)
        #expect(policy.shouldBlock(path: "id_ed25519") == true)
        #expect(policy.shouldBlock(path: ".ssh/id_rsa") == true)
    }

    @Test("PEM files are blocked")
    func pemBlocked() {
        #expect(policy.shouldBlock(path: "server.pem") == true)
        #expect(policy.shouldBlock(path: "cert.key") == true)
        #expect(policy.shouldBlock(path: "keystore.p12") == true)
    }

    @Test(".git directory is blocked")
    func gitInternalsBlocked() {
        #expect(policy.shouldBlock(path: ".git/HEAD") == true)
        #expect(policy.shouldBlock(path: ".git/config") == true)
    }

    @Test("node_modules is blocked")
    func nodeModulesBlocked() {
        #expect(policy.shouldBlock(path: "node_modules/express/index.js") == true)
    }

    @Test(".build directory is blocked")
    func buildDirectoryBlocked() {
        #expect(policy.shouldBlock(path: ".build/debug/Package.swift") == true)
    }

    @Test("DerivedData is blocked")
    func derivedDataBlocked() {
        #expect(policy.shouldBlock(path: "DerivedData/Build/Products/Debug/app") == true)
    }

    @Test("Normal Swift file is not blocked")
    func normalSwiftFileNotBlocked() {
        #expect(policy.shouldBlock(path: "Sources/Main.swift") == false)
        #expect(policy.shouldBlock(path: "Package.swift") == false)
        #expect(policy.shouldBlock(path: "README.md") == false)
    }

    @Test("Block reason returned for blocked files")
    func blockReasonReturned() {
        let reason = policy.blockReason(path: ".env")
        #expect(reason != nil)
        #expect(reason!.contains("Sensitive"))
    }

    @Test("No block reason for safe files")
    func noBlockReasonForSafe() {
        let reason = policy.blockReason(path: "Sources/Main.swift")
        #expect(reason == nil)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Approved Root Store Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Approved Root Store")
struct ApprovedRootStoreTests {

    @Test("Add and retrieve root")
    func addAndRetrieve() async throws {
        let store = InMemoryRootStore()
        let root = makeTestRoot()
        await store.add(root)
        let retrieved = await store.get(id: "test-root")
        #expect(retrieved != nil)
        #expect(retrieved?.displayName == "Test Root")
    }

    @Test("Remove root")
    func removeRoot() async throws {
        let store = InMemoryRootStore()
        await store.add(makeTestRoot())
        await store.remove(id: "test-root")
        let retrieved = await store.get(id: "test-root")
        #expect(retrieved == nil)
    }

    @Test("Find by path")
    func findByPath() async {
        let store = InMemoryRootStore()
        await store.add(makeTestRoot(path: "/Users/test/Project"))
        let found = await store.findByPath("/Users/test/Project")
        #expect(found != nil)
    }

    @Test("List all roots")
    func listAll() async {
        let store = InMemoryRootStore()
        await store.add(ApprovedRoot(id: "a", displayName: "A", absolutePath: "/a"))
        await store.add(ApprovedRoot(id: "b", displayName: "B", absolutePath: "/b"))
        let all = await store.list()
        #expect(all.count == 2)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Process Policy Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Process Policy")
struct ProcessPolicyTests {

    @Test("Default policy allows git, swift, xcrun")
    func defaultPolicyAllowsDevTools() {
        let policy = ProcessPolicy.v04C
        #expect(policy.allowedExecutables.contains("git"))
        #expect(policy.allowedExecutables.contains("swift"))
        #expect(policy.allowedExecutables.contains("xcrun"))
    }

    @Test("Blocked executables include shell and sudo")
    func blockedIncludesShellAndSudo() {
        #expect(ProcessPolicy.blockedExecutables.contains("bash"))
        #expect(ProcessPolicy.blockedExecutables.contains("sh"))
        #expect(ProcessPolicy.blockedExecutables.contains("sudo"))
        #expect(ProcessPolicy.blockedExecutables.contains("python"))
        #expect(ProcessPolicy.blockedExecutables.contains("node"))
        #expect(ProcessPolicy.blockedExecutables.contains("curl"))
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Streaming Process Runner Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Streaming Process Runner")
struct StreamingProcessRunnerTests {

    @Test("Allowed executable runs successfully")
    func allowedExecutableRuns() async throws {
        let runner = StreamingProcessRunner(policy: .v04C)
        let result = try await runner.run(
            executable: "git",
            arguments: ["--version"],
            workingDirectory: nil,
            environment: nil
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("git version"))
    }

    @Test("Blocked executable is rejected")
    func blockedExecutableRejected() async {
        let runner = StreamingProcessRunner(policy: .v04C)
        do {
            _ = try await runner.run(
                executable: "bash",
                arguments: ["-c", "echo hello"],
                workingDirectory: nil,
                environment: nil
            )
            Issue.record("Should have thrown")
        } catch is ProcessError {
            // expected
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test("Non-allowlisted executable is rejected")
    func nonAllowlistedRejected() async {
        let runner = StreamingProcessRunner(policy: .v04C)
        do {
            _ = try await runner.run(
                executable: "python3",
                arguments: ["-c", "print('hello')"],
                workingDirectory: nil,
                environment: nil
            )
            Issue.record("Should have thrown")
        } catch is ProcessError {
            // expected
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test("Shell injection in arguments is rejected")
    func shellInjectionRejected() async {
        let runner = StreamingProcessRunner(policy: .v04C)
        do {
            _ = try await runner.run(
                executable: "git",
                arguments: ["status", "; rm -rf /"],
                workingDirectory: nil,
                environment: nil
            )
            Issue.record("Should have thrown")
        } catch is ProcessError {
            // expected
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test("Pipe injection in arguments is rejected")
    func pipeInjectionRejected() async {
        let runner = StreamingProcessRunner(policy: .v04C)
        do {
            _ = try await runner.run(
                executable: "git",
                arguments: ["log", "| cat /etc/passwd"],
                workingDirectory: nil,
                environment: nil
            )
            Issue.record("Should have thrown")
        } catch is ProcessError {
            // expected
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test("Working directory outside approved root is rejected")
    func workDirOutsideRootRejected() async {
        let runner = StreamingProcessRunner(
            policy: .v04C,
            approvedRoots: ["/Users/test/Project"]
        )
        do {
            _ = try await runner.run(
                executable: "git",
                arguments: ["status"],
                workingDirectory: URL(fileURLWithPath: "/etc"),
                environment: nil
            )
            Issue.record("Should have thrown")
        } catch is ProcessError {
            // expected
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test("Working directory inside approved root is allowed")
    func workDirInsideRootAllowed() async throws {
        let runner = StreamingProcessRunner(
            policy: .v04C,
            approvedRoots: ["/tmp"]
        )
        let result = try await runner.run(
            executable: "git",
            arguments: ["--version"],
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            environment: nil
        )
        #expect(result.exitCode == 0)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Build Diagnostic Parser Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Build Diagnostic Parser")
struct BuildDiagnosticParserTests {
    let parser = BuildDiagnosticParser()

    @Test("Parses Swift error diagnostic")
    func parsesSwiftError() {
        let output = "/Sources/SwooshCore/AgentKernel.swift:42:17: error: cannot find 'ToolRegistry' in scope"
        let diagnostics = parser.parse(output)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .error)
        #expect(diagnostics[0].file?.contains("AgentKernel.swift") == true)
        #expect(diagnostics[0].line == 42)
        #expect(diagnostics[0].column == 17)
        #expect(diagnostics[0].message.contains("ToolRegistry"))
    }

    @Test("Parses warning diagnostic")
    func parsesWarning() {
        let output = "/Sources/SwooshTools/Tool.swift:88:9: warning: result of call to 'foo' is unused"
        let diagnostics = parser.parse(output)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .warning)
    }

    @Test("Parses multiple diagnostics")
    func parsesMultiple() {
        let output = """
        /File.swift:1:1: error: missing import
        /File.swift:5:3: warning: unused variable
        /File.swift:10:1: note: see declaration
        """
        let diagnostics = parser.parse(output)
        #expect(diagnostics.count == 3)
    }

    @Test("Parses Swift Testing test summary")
    func parsesTestSummary() {
        let output = """
        ✔ Test "foo" passed after 0.001 seconds.
        ✔ Test "bar" passed after 0.002 seconds.
        ✘ Test "baz" failed after 0.001 seconds.
        ✔ Test run with 3 tests in 1 suites passed after 0.003 seconds.
        """
        let summary = parser.parseTestSummary(output)
        // Counts individual ✔/✘ markers
        #expect(summary.passed >= 2)
        #expect(summary.failed >= 1)
    }

    @Test("Non-diagnostic lines are ignored")
    func nonDiagnosticIgnored() {
        let output = """
        Building for debugging...
        [1/5] Compiling SwooshCore AgentKernel.swift
        Build complete!
        """
        let diagnostics = parser.parse(output)
        #expect(diagnostics.isEmpty)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Integration: File Access with Approved Root
// ═══════════════════════════════════════════════════════════════

@Suite("Safe File Accessor Integration")
struct SafeFileAccessorIntegrationTests {

    @Test("resolveBookmark returns URL for known root")
    func resolveBookmarkReturnsURL() async throws {
        let store = InMemoryRootStore()
        await store.add(makeTestRoot(path: "/tmp/swoosh-test"))
        let accessor = SafeFileAccessor(rootStore: store)
        let url = try await accessor.resolveBookmark(id: "test-root")
        #expect(url.path == "/tmp/swoosh-test")
    }

    @Test("resolveBookmark throws for unknown root")
    func resolveBookmarkThrowsForUnknown() async {
        let store = InMemoryRootStore()
        let accessor = SafeFileAccessor(rootStore: store)
        do {
            _ = try await accessor.resolveBookmark(id: "nonexistent")
            Issue.record("Should have thrown")
        } catch is FileAccessError {
            // expected
        } catch {
            Issue.record("Wrong error type")
        }
    }

    @Test("deleteFile is disabled in 0.4C")
    func deleteFileDisabled() async {
        let store = InMemoryRootStore()
        let accessor = SafeFileAccessor(rootStore: store)
        do {
            try await accessor.deleteFile(
                root: URL(fileURLWithPath: "/tmp"),
                relativePath: "test.txt"
            )
            Issue.record("Should have thrown")
        } catch is FileAccessError {
            // expected - write not allowed
        } catch {
            Issue.record("Wrong error: \(error)")
        }
    }
}
