// SwooshCLI/ChatAskCommands.swift — Chat, Ask, Self-test commands

import ArgumentParser
import SwooshKit
import SwooshConfig
import SwooshStorage
import SwooshTUI
import SwooshProviders
import SwooshSecrets
import SwooshTools
import Foundation

// MARK: - Chat (Interactive Shell)

struct ChatCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "chat", abstract: "Start an interactive agent session.")

    @Flag(name: .shortAndLong, help: "Continue the last session.")
    var `continue` = false

    func run() async throws {
        let config = SwooshConfigStore()
        try? config.ensureDirectories()

        var status = ShellStatus()

        if let store = try? SwooshStateStore() {
            let approved = (try? await store.listApprovedMemories())?.count ?? 0
            let pending = (try? await store.listMemoryCandidates(status: "pending"))?.count ?? 0
            status.approvedMemoryCount = approved
            status.pendingCandidateCount = pending
        }

        let hw = HardwareDetector().detect()
        let secrets = KeychainSecretStore()
        var agentHandler: AgentHandler? = nil

        if let active = await ProviderFactory.detectActiveProvider(secrets: secrets) {
            status.model = active.model
            status.providerStatus = active.name

            let (router, _) = await ProviderFactory.buildRouter(secrets: secrets)
            let bridge = ProviderBridgeAdapter(router: router, role: .primaryChat, modelName: active.model)

            let sessionStore = InMemorySessionStore()
            let auditLogger = InMemoryResponseAuditor()

            if let store = try? SwooshStateStore() {
                let kernel = AgentKernel(
                    memoryLoader: StorageMemoryLoader(store: store),
                    reportLoader: StorageReportLoader(store: store),
                    permSummarizer: StoragePermissionSummarizer(store: store),
                    sessionStore: sessionStore,
                    auditLogger: auditLogger,
                    modelProvider: bridge
                )
                agentHandler = { input, sessionID in
                    let response = try await kernel.run(AgentRequest(sessionID: sessionID, input: input))
                    return (response: response.message, model: response.modelUsed)
                }
            } else {
                let kernel = AgentKernel(
                    memoryLoader: InMemoryMemoryLoader(),
                    reportLoader: InMemoryReportLoader(),
                    permSummarizer: InMemoryPermSummarizer(),
                    sessionStore: sessionStore,
                    auditLogger: auditLogger,
                    modelProvider: bridge
                )
                agentHandler = { input, sessionID in
                    let response = try await kernel.run(AgentRequest(sessionID: sessionID, input: input))
                    return (response: response.message, model: response.modelUsed)
                }
            }
        } else {
            if hw.hasAppleSilicon {
                let recs = hw.recommendedLocalModels.filter { $0.fits == .recommended || $0.fits == .feasible }
                if !recs.isEmpty {
                    status.model = "not configured (MLX-capable: \(recs.map(\.sizeLabel).joined(separator: ", ")))"
                }
            }
        }

        let registry = SlashCommandRegistry()
        await registry.registerAll(makeDefaultCommandDefinitions())

        let shell = SwooshShell(registry: registry, status: status, agentHandler: agentHandler)
        await shell.run()
    }
}

// MARK: - Ask (One-shot)

struct AskCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "ask", abstract: "Ask the agent a question (one-shot).")

    @Argument(help: "The question to ask.")
    var question: String

    func run() async throws {
        print("")
        print("  \u{001B}[36m⟳\u{001B}[0m Processing: \(question)")
        print("")

        let secrets = KeychainSecretStore()
        let modelProvider: SwooshCore.ModelProvider

        if let _ = await ProviderFactory.detectActiveProvider(secrets: secrets) {
            let (router, _) = await ProviderFactory.buildRouter(secrets: secrets)
            modelProvider = ProviderBridgeAdapter(router: router)
        } else {
            modelProvider = LocalStubProvider()
        }

        let memoryLoader: any MemoryContextLoading
        let reportLoader: any SetupReportLoading
        let permSummarizer: any PermissionSummarizing

        if let store = try? SwooshStateStore() {
            memoryLoader = StorageMemoryLoader(store: store)
            reportLoader = StorageReportLoader(store: store)
            permSummarizer = StoragePermissionSummarizer(store: store)
        } else {
            memoryLoader = InMemoryMemoryLoader()
            reportLoader = InMemoryReportLoader()
            permSummarizer = InMemoryPermSummarizer()
        }

        let kernel = AgentKernel(
            memoryLoader: memoryLoader,
            reportLoader: reportLoader,
            permSummarizer: permSummarizer,
            sessionStore: InMemorySessionStore(),
            auditLogger: InMemoryResponseAuditor(),
            modelProvider: modelProvider
        )

        let response = try await kernel.run(AgentRequest(input: question))

        let isStub = response.modelUsed.contains("stub")
        let icon = isStub ? "○" : "✓"
        let note = isStub ? " (stub — run `swoosh provider auth`)" : ""
        print("  \u{001B}[32m\(icon)\u{001B}[0m Response (model: \(response.modelUsed)\(note)):")
        print("")
        for line in response.message.components(separatedBy: "\n") {
            print("    \(line)")
        }
        print("")

        if !response.memoryIDsUsed.isEmpty {
            print("  Context: \(response.memoryIDsUsed.count) approved memories used.")
        }
        if response.setupReportUsed {
            print("  Context: Setup report included.")
        }
        print("  Run /why in interactive mode for full context audit.")
        print("")
    }
}

// MARK: - Self-test

struct SelfTestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "self-test", abstract: "Run a guided smoke test.")

    func run() async throws {
        print("Swoosh Self-Test\n")

        let config = SwooshConfigStore()
        let fm = FileManager.default

        check("Config directory", fm.fileExists(atPath: config.configDirectory.path))
        check("Config writable", fm.isWritableFile(atPath: config.configDirectory.path))
        await check("Keychain accessible", {
            let store = KeychainCredentialStore()
            _ = try await store.listKeys(service: "ai.swoosh.test")
            return true
        })

        let hardware = HardwareDetector().detect()
        check("Apple Silicon", hardware.hasAppleSilicon)
        check("Sufficient memory (≥8 GB)", hardware.totalMemoryGB >= 8)

        print()
        print("Run `swoosh doctor` for comprehensive diagnostics.")
    }

    private func check(_ name: String, _ condition: Bool) {
        print("  \(condition ? "✓" : "✗") \(name)")
    }

    private func check(_ name: String, _ condition: () async throws -> Bool) async {
        let result = (try? await condition()) ?? false
        print("  \(result ? "✓" : "✗") \(name)")
    }
}
