// SwooshCLI/PluginCommands.swift — Manage installed plugins via the daemon API
//
// All operations go through the bearer-gated `/api/plugins/*` surface on
// the local daemon. The CLI doesn't touch the plugin store, the firewall,
// or the tool registry directly — it's just the human-friendly way to
// drive the same humanOnly admin endpoints the iOS app uses.

import ArgumentParser
import Foundation
import SwooshClient
import SwooshConfig

struct PluginCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plugin",
        abstract: "List, install, and toggle plugins through the daemon.",
        subcommands: [
            PluginListCommand.self,
            PluginStatusCommand.self,
            PluginInstallCommand.self,
            PluginUninstallCommand.self,
            PluginEnableCommand.self,
            PluginDisableCommand.self,
        ],
        defaultSubcommand: PluginListCommand.self
    )
}

// MARK: - Shared options

struct PluginDaemonOptions: ParsableArguments {
    @Option(name: .long, help: "Daemon host (default: 127.0.0.1).")
    var host: String = "127.0.0.1"

    @Option(name: .long, help: "Daemon port (default: 8787).")
    var port: Int = 8787

    @Option(name: .customLong("config-dir"), help: "State directory holding api_token (default: ~/.swoosh).")
    var configDirectory: String?

    func makeClient() throws -> SwooshAPIClient {
        let config = makeSwooshConfigStore(configDirectory: configDirectory)
        let token = (try? String(contentsOf: config.apiTokenFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: "http://\(host):\(port)") else {
            throw ValidationError("invalid host:port — \(host):\(port)")
        }
        return SwooshAPIClient(baseURL: baseURL, token: token)
    }
}

// MARK: - list

struct PluginListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List installed plugins and their enabled state."
    )

    @OptionGroup var daemon: PluginDaemonOptions

    @Flag(name: .long, help: "Output JSON.")
    var json = false

    func run() async throws {
        let client = try daemon.makeClient()
        let response = try await client.plugins()
        if json {
            let data = try JSONEncoder.swooshCLI.encode(response)
            print(String(data: data, encoding: .utf8) ?? "{}")
            return
        }
        guard !response.plugins.isEmpty else {
            print("No plugins installed. Drop a plugin dir into ~/.swoosh/plugins/<id>/ or run `swoosh plugin install <path>`.")
            return
        }
        print("ID                       KIND        STATE     VERSION  NAME")
        for plugin in response.plugins {
            let id = plugin.id.padding(toLength: 24, withPad: " ", startingAt: 0)
            let kind = plugin.kind.padding(toLength: 11, withPad: " ", startingAt: 0)
            let state = (plugin.enabled ? "enabled" : "disabled").padding(toLength: 9, withPad: " ", startingAt: 0)
            let ver = plugin.version.padding(toLength: 8, withPad: " ", startingAt: 0)
            print("\(id) \(kind) \(state) \(ver) \(plugin.name)")
        }
    }
}

// MARK: - status

struct PluginStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show a plugin's manifest, granted permissions, and recent events."
    )

    @OptionGroup var daemon: PluginDaemonOptions

    @Argument(help: "Plugin id.")
    var id: String

    @Flag(name: .long, help: "Output JSON.")
    var json = false

    func run() async throws {
        let client = try daemon.makeClient()
        let detail = try await client.plugin(id: id)
        if json {
            let data = try JSONEncoder.swooshCLI.encode(detail)
            print(String(data: data, encoding: .utf8) ?? "{}")
            return
        }
        let plugin = detail.plugin
        print("Plugin: \(plugin.name) v\(plugin.version)  [\(plugin.id)]")
        if let description = plugin.description { print("  \(description)") }
        if let author = plugin.author { print("Author: \(author)") }
        print("Kind:    \(plugin.kind)")
        print("Enabled: \(plugin.enabled)")
        print("Requested permissions: \(plugin.requestedPermissions.joined(separator: ", "))")
        if !detail.grantedPermissions.isEmpty {
            print("Currently granted:     \(detail.grantedPermissions.joined(separator: ", "))")
        }
        if !plugin.tools.isEmpty {
            print("Tools:")
            for tool in plugin.tools {
                let approval = tool.requiresApproval ? "approval" : "no approval"
                print("  • \(tool.name) [\(tool.permission), \(tool.risk), \(approval)] — \(tool.description)")
            }
        }
        if !detail.auditTail.isEmpty {
            print("Recent events:")
            let iso = ISO8601DateFormatter()
            for event in detail.auditTail.suffix(10) {
                print("  \(iso.string(from: event.createdAt))  \(event.kind.padding(toLength: 16, withPad: " ", startingAt: 0)) \(event.message)")
            }
        }
    }
}

// MARK: - install

struct PluginInstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install a plugin from a local directory (must contain manifest.json). Lands disabled."
    )

    @OptionGroup var daemon: PluginDaemonOptions

    @Argument(help: "Path to a directory containing manifest.json.")
    var path: String

    @Flag(name: .long, help: "Also enable the plugin after installing.")
    var enable = false

    func run() async throws {
        let absolutePath = NSString(string: path).expandingTildeInPath
        let resolved: String
        if absolutePath.hasPrefix("/") {
            resolved = absolutePath
        } else {
            resolved = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(absolutePath).standardizedFileURL.path
        }
        let client = try daemon.makeClient()
        let response = try await client.installPlugin(sourcePath: resolved)
        print(response.message)
        print("  installed at: ~/.swoosh/plugins/\(response.plugin.id)/")
        if enable {
            let enabled = try await client.enablePlugin(id: response.plugin.id)
            print(enabled.message)
        }
    }
}

// MARK: - uninstall

struct PluginUninstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Disable (if enabled) and remove a plugin."
    )

    @OptionGroup var daemon: PluginDaemonOptions

    @Argument(help: "Plugin id.")
    var id: String

    func run() async throws {
        let client = try daemon.makeClient()
        _ = try await client.uninstallPlugin(id: id)
        print("Uninstalled \(id).")
    }
}

// MARK: - enable / disable

struct PluginEnableCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "enable",
        abstract: "Enable an installed plugin. Grants its requested permissions."
    )

    @OptionGroup var daemon: PluginDaemonOptions

    @Argument(help: "Plugin id.")
    var id: String

    func run() async throws {
        let client = try daemon.makeClient()
        let response = try await client.enablePlugin(id: id)
        print(response.message)
    }
}

struct PluginDisableCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disable",
        abstract: "Disable an enabled plugin. Removes its tools and revokes any permissions only this plugin held."
    )

    @OptionGroup var daemon: PluginDaemonOptions

    @Argument(help: "Plugin id.")
    var id: String

    func run() async throws {
        let client = try daemon.makeClient()
        let response = try await client.disablePlugin(id: id)
        print(response.message)
    }
}
