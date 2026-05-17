// Tests/SwooshTUITests/SlashCommandTests.swift

import Testing
@testable import SwooshTUI

@Test func testHelpListsCoreCommands() async throws {
    let registry = SlashCommandRegistry()
    await registerDefaultCommands(on: registry)

    let helpText = await registry.helpText()
    #expect(helpText.contains("/help"))
    #expect(helpText.contains("/exit"))
    #expect(helpText.contains("/scout"))
    #expect(helpText.contains("/vault"))
    #expect(helpText.contains("/permissions"))
    #expect(helpText.contains("/why"))
    #expect(helpText.contains("/repeat"))
    #expect(helpText.contains("/model"))
    #expect(helpText.contains("/tools"))
    #expect(helpText.contains("/db"))
    #expect(helpText.contains("/local"))
    #expect(helpText.contains("/firewall"))
}

@Test func testUnknownSlashCommandReturnsCleanError() async throws {
    let registry = SlashCommandRegistry()
    await registerDefaultCommands(on: registry)

    let result = await registry.execute("nonexistent", context: SlashCommandContext())
    guard case .error(let msg) = result else {
        #expect(Bool(false), "Expected error result")
        return
    }
    #expect(msg.contains("Unknown command"))
    #expect(msg.contains("/nonexistent"))
}

@Test func testAliasResolution() async throws {
    let registry = SlashCommandRegistry()
    await registerDefaultCommands(on: registry)

    // /h should resolve to /help
    let helpCmd = await registry.lookup("h")
    #expect(helpCmd != nil)
    #expect(helpCmd?.name == "help")

    // /q should resolve to /exit
    let exitCmd = await registry.lookup("q")
    #expect(exitCmd != nil)
    #expect(exitCmd?.name == "exit")

    // /v should resolve to /vault
    let vaultCmd = await registry.lookup("v")
    #expect(vaultCmd != nil)
    #expect(vaultCmd?.name == "vault")

    // /memory should resolve to /vault
    let memoryCmd = await registry.lookup("memory")
    #expect(memoryCmd != nil)
    #expect(memoryCmd?.name == "vault")

    // /perms and /p should resolve to /permissions
    let permsCmd = await registry.lookup("perms")
    #expect(permsCmd != nil)
    #expect(permsCmd?.name == "permissions")
}

@Test func testExitCommandReturnsExit() async throws {
    let registry = SlashCommandRegistry()
    await registerDefaultCommands(on: registry)

    let result = await registry.execute("exit", context: SlashCommandContext())
    guard case .exit = result else {
        #expect(Bool(false), "Expected .exit result")
        return
    }
}

@Test func testParseSlashCommand() async throws {
    let registry = SlashCommandRegistry()
    await registerDefaultCommands(on: registry)

    // Slash command should parse
    let result = await registry.parse(line: "/help")
    #expect(result != nil)

    // Non-slash should return nil
    let plain = await registry.parse(line: "hello world")
    #expect(plain == nil)

    // Empty slash should return nil
    let empty = await registry.parse(line: "/")
    #expect(empty == nil)
}

@Test func testCommandCategories() async throws {
    let registry = SlashCommandRegistry()
    await registerDefaultCommands(on: registry)

    let sorted = await registry.sortedCommands()
    let categories = Set(sorted.map { $0.category })

    #expect(categories.contains(.general))
    #expect(categories.contains(.agent))
    #expect(categories.contains(.personalization))
    #expect(categories.contains(.system))
    #expect(categories.contains(.development))
}

@Test func testVaultSubcommands() async throws {
    let registry = SlashCommandRegistry()
    await registerDefaultCommands(on: registry)

    let pendingResult = await registry.parse(line: "/vault pending")
    guard case .success(let msg) = pendingResult else {
        #expect(Bool(false), "Expected success")
        return
    }
    #expect(msg.contains("Pending"))

    let approvedResult = await registry.parse(line: "/vault approved")
    guard case .success(let msg2) = approvedResult else {
        #expect(Bool(false), "Expected success")
        return
    }
    #expect(msg2.contains("Approved"))
}

@Test func testAllCommandsRegistered() async throws {
    let registry = SlashCommandRegistry()
    await registerDefaultCommands(on: registry)

    let expectedCommands = [
        "help", "exit", "clear", "status",
        "model", "tools", "sessions", "why", "repeat",
        "scout", "vault",
        "permissions", "firewall",
        "local", "db"
    ]

    for name in expectedCommands {
        let cmd = await registry.lookup(name)
        #expect(cmd != nil, "Missing command: /\(name)")
    }
}
