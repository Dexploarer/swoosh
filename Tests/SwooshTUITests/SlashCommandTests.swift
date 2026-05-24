// Tests/SwooshTUITests/SlashCommandTests.swift — 0.9S
//
// Slash-command registry tests. The 0.9S overhaul trimmed the prose-
// only commands (/scout, /doctor, /permissions, /firewall, /budget,
// /status, /model, /why, /repeat) and wired /help to the live
// registry, so these tests now check the surviving in-shell command
// set, the help renderer round-trip, and the registry contract.

import Testing
@testable import SwooshTUI

private func makeRegistry() async -> SlashCommandRegistry {
    let registry = SlashCommandRegistry()
    await registry.registerAll(makeDefaultCommandDefinitions(registry: registry))
    return registry
}

@Test func testHelpRendersFromLiveRegistry() async throws {
    let registry = await makeRegistry()
    // `/help` should call registry.helpText(), which iterates
    // the live command map — adding or removing a command shows up
    // in the next `/help` output without touching a hand-typed literal.
    let result = await registry.execute("help", context: SlashCommandContext())
    guard case .success(let text) = result else {
        Issue.record("Expected /help to return .success, got \(result)")
        return
    }
    #expect(text.contains("/help"))
    #expect(text.contains("/exit"))
    #expect(text.contains("/vault"))
    #expect(text.contains("/local"))
    #expect(text.contains("Swoosh Commands"))
}

@Test func testHelpAutoSurfacesNewlyRegisteredCommand() async throws {
    let registry = await makeRegistry()
    // Register a custom command and assert /help picks it up.
    let custom = SlashCommandDefinition(
        name: "audit-test-cmd",
        summary: "Auto-surfaced from the live registry.",
        category: .general,
        handler: { _ in .success("") }
    )
    await registry.register(custom)
    let result = await registry.execute("help", context: SlashCommandContext())
    guard case .success(let text) = result else {
        Issue.record("Expected /help to return .success")
        return
    }
    #expect(text.contains("/audit-test-cmd"),
            "Newly-registered commands must auto-surface in /help")
}

@Test func testUnknownSlashCommandReturnsCleanError() async throws {
    let registry = await makeRegistry()
    let result = await registry.execute("nonexistent", context: SlashCommandContext())
    guard case .error(let msg) = result else {
        Issue.record("Expected .error result")
        return
    }
    #expect(msg.contains("Unknown command"))
    #expect(msg.contains("/nonexistent"))
}

@Test func testAliasResolution() async throws {
    let registry = await makeRegistry()
    let helpCmd = await registry.lookup("h")
    #expect(helpCmd?.name == "help")
    let exitCmd = await registry.lookup("q")
    #expect(exitCmd?.name == "exit")
    let vaultCmd = await registry.lookup("v")
    #expect(vaultCmd?.name == "vault")
    let memoryCmd = await registry.lookup("memory")
    #expect(memoryCmd?.name == "vault")
}

@Test func testExitCommandReturnsExit() async throws {
    let registry = await makeRegistry()
    let result = await registry.execute("exit", context: SlashCommandContext())
    guard case .exit = result else {
        Issue.record("Expected .exit result")
        return
    }
}

@Test func testParseSlashCommand() async throws {
    let registry = await makeRegistry()
    let result = await registry.parse(line: "/help")
    #expect(result != nil)
    let plain = await registry.parse(line: "hello world")
    #expect(plain == nil)
    let empty = await registry.parse(line: "/")
    #expect(empty == nil)
}

@Test func testCommandCategories() async throws {
    let registry = await makeRegistry()
    let sorted = await registry.sortedCommands()
    let categories = Set(sorted.map { $0.category })
    #expect(categories.contains(.general))
    #expect(categories.contains(.agent))
    #expect(categories.contains(.personalization))
    #expect(categories.contains(.development))
    // .system removed — all prose-stub system commands were trimmed in 0.9S
    #expect(!categories.contains(.system),
            "All .system commands were prose stubs and removed in 0.9S")
}

@Test func testVaultSubcommands() async throws {
    let registry = await makeRegistry()
    let pendingResult = await registry.parse(line: "/vault pending")
    guard case .success(let msg) = pendingResult else {
        Issue.record("Expected success")
        return
    }
    #expect(msg.contains("Pending"))
    let approvedResult = await registry.parse(line: "/vault approved")
    guard case .success(let msg2) = approvedResult else {
        Issue.record("Expected success")
        return
    }
    #expect(msg2.contains("Approved"))
}

@Test func testShippedCommandSet() async throws {
    let registry = await makeRegistry()
    // Pinned set of in-shell commands after the 0.9S trim. Anything
    // here being absent is a regression; anything new appearing without
    // a test update is a deliberate addition.
    let expected = [
        "help", "exit", "clear",
        "tools", "sessions",
        "vault",
        "local", "skills", "db"
    ]
    for name in expected {
        let cmd = await registry.lookup(name)
        #expect(cmd != nil, "Missing command: /\(name)")
    }
    // Prose stubs deliberately removed in 0.9S — make sure they don't
    // sneak back in as drift.
    for trimmed in ["status", "model", "why", "repeat", "scout",
                    "doctor", "permissions", "firewall", "budget"] {
        let cmd = await registry.lookup(trimmed)
        #expect(cmd == nil, "Prose-stub /\(trimmed) was removed in 0.9S; reintroduce only with a real implementation.")
    }
}
