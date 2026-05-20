// SwooshCLI/TerminalCommands.swift — Terminal backend options
import ArgumentParser
import Foundation
import SwooshToolsets

struct TerminalCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "terminal",
        abstract: "List and configure terminal execution backends.",
        subcommands: [
            TerminalBackendsCommand.self,
            TerminalConfigureCommand.self,
        ],
        defaultSubcommand: TerminalBackendsCommand.self
    )
}

struct TerminalBackendsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "backends", abstract: "List terminal backend options.")

    @Flag(name: .long, help: "Output JSON.")
    var json = false

    func run() async throws {
        let config = try await TerminalConfigStore().load()
        let statuses = TerminalBackend.allCases.map { terminalBackendStatus(for: $0, config: config) }
        if json {
            let data = try JSONEncoder.swooshCLI.encode(statuses)
            print(String(data: data, encoding: .utf8) ?? "[]")
            return
        }
        print("Active: \(config.backend.rawValue)\n")
        for status in statuses {
            let available = status.available ? "available" : "missing"
            let configured = status.configured ? "configured" : "not configured"
            print("\(status.backend.rawValue.padding(toLength: 15, withPad: " ", startingAt: 0)) \(available), \(configured) — \(status.detail)")
        }
    }
}

struct TerminalConfigureCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "configure", abstract: "Set the default terminal backend.")

    @Argument(help: "Backend: local, docker, ssh, singularity, modal, daytona, or vercelSandbox.")
    var backend: TerminalBackend

    @Option(name: .long, help: "Default working directory.")
    var cwd: String?

    @Option(name: .long, help: "Docker or Podman image.")
    var dockerImage: String?

    @Option(name: .long, help: "SSH host.")
    var sshHost: String?

    @Option(name: .long, help: "SSH user.")
    var sshUser: String?

    @Option(name: .long, help: "SSH key path.")
    var sshKeyPath: String?

    @Option(name: .long, help: "Apptainer or Singularity image path.")
    var singularityImage: String?

    @Option(name: .long, help: "Modal image or runtime label.")
    var modalImage: String?

    @Option(name: .long, help: "Daytona image or workspace label.")
    var daytonaImage: String?

    @Option(name: .long, help: "Vercel sandbox runtime label.")
    var vercelRuntime: String?

    func run() async throws {
        let store = TerminalConfigStore()
        var config = try await store.load()
        config.backend = backend
        if let cwd { config.cwd = cwd }
        if let dockerImage { config.dockerImage = dockerImage }
        if let sshHost { config.sshHost = sshHost }
        if let sshUser { config.sshUser = sshUser }
        if let sshKeyPath { config.sshKeyPath = sshKeyPath }
        if let singularityImage { config.singularityImage = singularityImage }
        if let modalImage { config.modalImage = modalImage }
        if let daytonaImage { config.daytonaImage = daytonaImage }
        if let vercelRuntime { config.vercelRuntime = vercelRuntime }
        try await store.save(config)
        print("Terminal backend set to \(backend.rawValue).")
    }
}

extension TerminalBackend: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument)
    }
}
