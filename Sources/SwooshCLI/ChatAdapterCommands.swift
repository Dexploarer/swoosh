// SwooshCLI/ChatAdapterCommands.swift — Toggle chat platform adapters — 0.4B
import ArgumentParser
import Foundation
import SwooshClient
import SwooshChatSDK

struct ChatAdaptersCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "chat-adapters",
        abstract: "List and toggle chat platform adapters.",
        subcommands: [
            ChatAdaptersListCommand.self,
            ChatAdaptersEnableCommand.self,
            ChatAdaptersDisableCommand.self,
        ],
        defaultSubcommand: ChatAdaptersListCommand.self
    )
}

struct ChatAdaptersListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List available chat adapters.")

    @Flag(name: .long, help: "Output JSON.")
    var json = false

    func run() async throws {
        let store = ChatAdapterToggleStore()
        let stateStore = ChatStateAdapterToggleStore()
        let catalog = ChatAdapterCatalog()
        let stateCatalog = ChatStateAdapterCatalog()
        let statuses = try await catalog.statuses(store: store)
        let stateStatuses = try await stateCatalog.statuses(store: stateStore)
        if json {
            let response = ChatAdapterProjection.response(platformStatuses: statuses, stateStatuses: stateStatuses)
            let data = try JSONEncoder.swooshCLI.encode(response)
            print(String(data: data, encoding: .utf8) ?? "{}")
            return
        }
        print("Chat platform adapters\n")
        for status in statuses {
            let enabled = status.enabled ? "on " : "off"
            let configured = adapterConfigurationSummary(configured: status.configured, missing: status.missingCredentials, notes: status.configurationNotes)
            let package = status.definition.packageName.map { " \($0)" } ?? ""
            print("\(enabled) \(status.definition.id.padding(toLength: 18, withPad: " ", startingAt: 0)) \(status.definition.displayName)\(package) — \(status.definition.distribution.rawValue), \(configured)")
        }
        print("\nChat state adapters\n")
        for status in stateStatuses {
            let enabled = status.enabled ? "on " : "off"
            let configured = adapterConfigurationSummary(configured: status.configured, missing: status.missingCredentials, notes: status.configurationNotes)
            let package = status.definition.packageName.map { " \($0)" } ?? ""
            let production = status.definition.productionReady ? "production" : "dev/test"
            print("\(enabled) \(status.definition.id.padding(toLength: 18, withPad: " ", startingAt: 0)) \(status.definition.displayName)\(package) — \(status.definition.distribution.rawValue), \(production), \(configured)")
        }
    }
}

struct ChatAdaptersEnableCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "enable", abstract: "Enable a chat adapter.")

    @Argument(help: "Adapter id, for example slack, discord, telegram, github, linear, web, swoosh.")
    var id: String

    func run() async throws {
        try await set(id: id, enabled: true)
    }
}

struct ChatAdaptersDisableCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "disable", abstract: "Disable a chat adapter.")

    @Argument(help: "Adapter id.")
    var id: String

    func run() async throws {
        try await set(id: id, enabled: false)
    }
}

private func set(id: String, enabled: Bool) async throws {
    if let kind = ChatAdapterKind(rawValue: id) {
        let store = ChatAdapterToggleStore()
        try await store.set(kind, enabled: enabled)
        print("\(enabled ? "Enabled" : "Disabled") \(id).")
        return
    }
    if let kind = ChatStateAdapterKind(rawValue: id) {
        let store = ChatStateAdapterToggleStore()
        try await store.set(kind, enabled: enabled)
        print("\(enabled ? "Enabled" : "Disabled") \(id).")
        return
    }
    do {
        throw ValidationError("Unknown adapter '\(id)'. Run `swoosh chat-adapters list`.")
    }
}

private func adapterConfigurationSummary(configured: Bool, missing: [String], notes: [String]) -> String {
    if configured { return "configured" }
    if !missing.isEmpty { return "missing \(missing.joined(separator: ", "))" }
    return notes.first ?? "manual configuration required"
}
