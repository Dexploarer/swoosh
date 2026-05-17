// SwooshTUI/SlashCommand.swift — Slash command registry
//
// Reusable by CLI shell, future TUI, and future messaging gateway.
// Commands are async-capable, protocol-based, and registry-managed.

import Foundation

// MARK: - Types

/// The result of executing a slash command.
public enum SlashCommandResult: Sendable {
    case success(String)
    case error(String)
    case exit
    case multiline([String])
}

/// Context provided to every slash command handler.
public struct SlashCommandContext: Sendable {
    public let arguments: [String]
    public let rawInput: String
    public let sessionID: String

    public init(arguments: [String] = [], rawInput: String = "", sessionID: String = "default") {
        self.arguments = arguments
        self.rawInput = rawInput
        self.sessionID = sessionID
    }
}

/// A registered slash command definition.
public struct SlashCommandDefinition: Sendable {
    public let name: String
    public let aliases: [String]
    public let summary: String
    public let usage: String?
    public let category: CommandCategory
    public let handler: @Sendable (SlashCommandContext) async -> SlashCommandResult

    public init(
        name: String,
        aliases: [String] = [],
        summary: String,
        usage: String? = nil,
        category: CommandCategory = .general,
        handler: @escaping @Sendable (SlashCommandContext) async -> SlashCommandResult
    ) {
        self.name = name
        self.aliases = aliases
        self.summary = summary
        self.usage = usage
        self.category = category
        self.handler = handler
    }
}

/// Command categories for grouping in /help output.
public enum CommandCategory: String, Sendable, CaseIterable {
    case general = "General"
    case agent = "Agent"
    case personalization = "Personalization"
    case system = "System"
    case development = "Development"
}

// MARK: - Registry

/// Thread-safe slash command registry. Used by CLI shell, TUI, and gateway.
public actor SlashCommandRegistry {
    private var commands: [String: SlashCommandDefinition] = [:]
    private var aliasMap: [String: String] = [:]

    public init() {}

    /// Register a command.
    public func register(_ definition: SlashCommandDefinition) {
        commands[definition.name] = definition
        for alias in definition.aliases {
            aliasMap[alias] = definition.name
        }
    }

    /// Register multiple commands at once.
    public func registerAll(_ definitions: [SlashCommandDefinition]) {
        for def in definitions {
            register(def)
        }
    }

    /// Look up a command by name or alias.
    public func lookup(_ name: String) -> SlashCommandDefinition? {
        let normalized = name.lowercased()
        if let cmd = commands[normalized] { return cmd }
        if let canonical = aliasMap[normalized], let cmd = commands[canonical] { return cmd }
        return nil
    }

    /// Execute a command by name with context.
    public func execute(_ name: String, context: SlashCommandContext) async -> SlashCommandResult {
        guard let cmd = lookup(name) else {
            let available = sortedCommands().map { "/\($0.name)" }.joined(separator: ", ")
            return .error("Unknown command: /\(name). Available: \(available)")
        }
        return await cmd.handler(context)
    }

    /// Parse a raw slash command string and execute it.
    public func parse(line: String, sessionID: String = "default") async -> SlashCommandResult? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else { return nil }

        let parts = trimmed.dropFirst().split(separator: " ", maxSplits: 1).map(String.init)
        guard let name = parts.first else { return nil }

        let args = parts.count > 1
            ? parts[1].split(separator: " ").map(String.init)
            : []

        let context = SlashCommandContext(
            arguments: args,
            rawInput: parts.count > 1 ? parts[1] : "",
            sessionID: sessionID
        )

        return await execute(name, context: context)
    }

    /// All registered commands sorted by category then name.
    public func sortedCommands() -> [SlashCommandDefinition] {
        commands.values.sorted { a, b in
            if a.category.rawValue != b.category.rawValue {
                return a.category.rawValue < b.category.rawValue
            }
            return a.name < b.name
        }
    }

    /// All command names (including aliases).
    public func allNames() -> [String] {
        Array(commands.keys) + Array(aliasMap.keys)
    }

    /// Generate help text.
    public func helpText() -> String {
        var lines: [String] = ["", "─── Swoosh Commands ───────────────────────────", ""]
        var currentCategory = ""

        for cmd in sortedCommands() {
            if cmd.category.rawValue != currentCategory {
                currentCategory = cmd.category.rawValue
                lines.append("  \(currentCategory)")
            }

            let aliasStr = cmd.aliases.isEmpty ? "" : " (aliases: \(cmd.aliases.map { "/\($0)" }.joined(separator: ", ")))"
            lines.append("    /\(cmd.name.padding(toLength: 14, withPad: " ", startingAt: 0)) \(cmd.summary)\(aliasStr)")
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }
}
