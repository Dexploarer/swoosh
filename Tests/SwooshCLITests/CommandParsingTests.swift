// Tests/SwooshCLITests/CommandParsingTests.swift — Argument-parser checks — 0.4A
//
// These tests reach the real command types via `@testable import
// SwooshCLI` (possible because SwooshCLI is now a library target — see
// the audit follow-up). They are the only thing that guarantees a typo
// in an `@Option`/`@Flag` name will fail CI rather than ship silently.

import Testing
import Foundation
import ArgumentParser
@testable import SwooshCLI

@Suite("Argument parsing — root")
struct RootParsingTests {
    @Test("swoosh root command parses with no args (defaults to chat)")
    func rootDefaultsToChat() throws {
        let command = try SwooshCommand.parseAsRoot([])
        #expect(command is ChatCommand)
    }

    @Test("swoosh chat parses with no flags (no --continue today)")
    func chatBareCommand() throws {
        let command = try SwooshCommand.parseAsRoot(["chat"])
        #expect(command is ChatCommand)
    }

    @Test("swoosh chat --continue is rejected — flag was unimplemented and removed")
    func chatContinueFlagRemoved() throws {
        #expect(throws: (any Error).self) {
            _ = try SwooshCommand.parseAsRoot(["chat", "--continue"])
        }
    }

    @Test("swoosh ask <question> parses")
    func askPositional() throws {
        let command = try SwooshCommand.parseAsRoot(["ask", "what time is it"])
        let ask = try #require(command as? AskCommand)
        #expect(ask.question == "what time is it")
        #expect(ask.session == "default")
    }

    @Test("swoosh doctor --fix --json --config-dir parses")
    func doctorFullOptions() throws {
        let command = try SwooshCommand.parseAsRoot([
            "doctor", "--fix", "--json", "--config-dir", "/tmp/foo",
        ])
        let doctor = try #require(command as? DoctorCommand)
        #expect(doctor.scaffold == true)
        #expect(doctor.json == true)
        #expect(doctor.configDirectory == "/tmp/foo")
    }
}

@Suite("Argument parsing — setup")
struct SetupParsingTests {
    @Test("swoosh setup parses with no subcommand and defaults to quick")
    func setupDefaultsToQuick() throws {
        let command = try SwooshCommand.parseAsRoot(["setup"])
        #expect(command is SetupQuickCommand)
    }

    @Test("swoosh setup quick parses --non-interactive and presets")
    func quickNonInteractive() throws {
        let command = try SwooshCommand.parseAsRoot([
            "setup", "quick",
            "--non-interactive",
            "--model-path", "hybrid",
            "--permission-profile", "developer",
            "--daemon-port", "9090",
        ])
        let quick = try #require(command as? SetupQuickCommand)
        #expect(quick.nonInteractive == true)
        #expect(quick.requestedModelPath == .hybrid)
        #expect(quick.requestedPermissionProfile?.rawValue == "developer")
        #expect(quick.daemonPort == 9090)
    }

    @Test("swoosh setup full parses --config-dir")
    func fullConfigDir() throws {
        let command = try SwooshCommand.parseAsRoot([
            "setup", "full", "--config-dir", "/tmp/swoosh",
        ])
        let full = try #require(command as? SetupFullCommand)
        #expect(full.configDirectory == "/tmp/swoosh")
    }

    @Test("swoosh setup developer parses")
    func developerParses() throws {
        let command = try SwooshCommand.parseAsRoot(["setup", "developer"])
        #expect(command is SetupDeveloperCommand)
    }

    @Test("swoosh setup server parses")
    func serverParses() throws {
        let command = try SwooshCommand.parseAsRoot(["setup", "server"])
        #expect(command is SetupServerCommand)
    }

    @Test("Removed placeholder setup subcommands no longer parse")
    func placeholderSubcommandsRejected() throws {
        for removed in ["model", "permissions", "memory", "gateway", "tools", "terminal", "local-model", "import-hermes"] {
            // `swoosh setup <removed>` should fail because the subcommand
            // is gone. We accept either a parse failure or a successful
            // re-parse as a *different* command type (e.g. "model" might
            // route to the root `ModelCommand`), but never to a stale
            // setup-stub instance.
            if let parsed = try? SwooshCommand.parseAsRoot(["setup", removed]) {
                #expect(!String(describing: type(of: parsed)).contains("Setup\(removed.capitalized)Command"))
            }
        }
    }
}

@Suite("Argument parsing — scout / memory")
struct ScoutMemoryParsingTests {
    @Test("swoosh scout run --depth --folders parses")
    func scoutRun() throws {
        let command = try SwooshCommand.parseAsRoot([
            "scout", "run", "--depth", "deep", "--folders", "/tmp,/var",
        ])
        let run = try #require(command as? ScoutRunCommand)
        #expect(run.depth == "deep")
        #expect(run.folders == "/tmp,/var")
    }

    @Test("swoosh scout report parses")
    func scoutReport() throws {
        let command = try SwooshCommand.parseAsRoot(["scout", "report"])
        #expect(command is ScoutReportCommand)
    }

    @Test("swoosh memory list --status parses")
    func memoryList() throws {
        let command = try SwooshCommand.parseAsRoot(["memory", "list", "--status", "approved"])
        let list = try #require(command as? MemoryListCommand)
        #expect(list.status == "approved")
    }

    @Test("swoosh memory approve --all parses")
    func memoryApproveAll() throws {
        let command = try SwooshCommand.parseAsRoot(["memory", "approve", "--all"])
        let approve = try #require(command as? MemoryApproveCommand)
        #expect(approve.all == true)
    }

    @Test("swoosh memory reject --id --reason --force parses")
    func memoryReject() throws {
        let command = try SwooshCommand.parseAsRoot([
            "memory", "reject", "--id", "abc123", "--reason", "duplicate", "--force",
        ])
        let reject = try #require(command as? MemoryRejectCommand)
        #expect(reject.id == "abc123")
        #expect(reject.reason == "duplicate")
        #expect(reject.force == true)
    }

    @Test("swoosh permissions --status parses")
    func permissionsStatus() throws {
        let command = try SwooshCommand.parseAsRoot(["permissions", "--status"])
        let perms = try #require(command as? PermissionsCommand)
        #expect(perms.status == true)
    }
}

@Suite("Argument parsing — providers / chat-adapters / terminal")
struct ProviderParsingTests {
    @Test("swoosh provider list parses")
    func providerList() throws {
        let command = try SwooshCommand.parseAsRoot(["provider", "list"])
        #expect(command is ProviderListCommand)
    }

    @Test("swoosh provider auth openai --api-key parses")
    func providerAuth() throws {
        let command = try SwooshCommand.parseAsRoot([
            "provider", "auth", "openai", "--api-key", "sk-test",
        ])
        let auth = try #require(command as? ProviderAuthCommand)
        #expect(auth.provider == "openai")
        #expect(auth.apiKey == "sk-test")
        #expect(auth.pkce == false)
    }

    @Test("swoosh provider auth openrouter --pkce parses")
    func providerAuthPKCE() throws {
        let command = try SwooshCommand.parseAsRoot([
            "provider", "auth", "openrouter", "--pkce",
        ])
        let auth = try #require(command as? ProviderAuthCommand)
        #expect(auth.pkce == true)
    }

    @Test("swoosh provider test [name] parses")
    func providerTest() throws {
        let any = try SwooshCommand.parseAsRoot(["provider", "test"])
        #expect(any is ProviderTestCommand)
        let one = try SwooshCommand.parseAsRoot(["provider", "test", "openai"])
        let cmd = try #require(one as? ProviderTestCommand)
        #expect(cmd.provider == "openai")
    }

    @Test("swoosh provider discover parses")
    func providerDiscover() throws {
        let command = try SwooshCommand.parseAsRoot(["provider", "discover"])
        #expect(command is ProviderDiscoverCommand)
    }

    @Test("swoosh provider select <id> parses the active-provider id")
    func providerSelect() throws {
        let command = try SwooshCommand.parseAsRoot(["provider", "select", "dev-proxy"])
        let select = try #require(command as? ProviderSelectCommand)
        #expect(select.provider == "dev-proxy")
    }

    @Test("swoosh provider select with no id is rejected (required arg)")
    func providerSelectRequiresID() throws {
        #expect(throws: (any Error).self) {
            _ = try SwooshCommand.parseAsRoot(["provider", "select"])
        }
    }

    @Test("swoosh chat-adapters list --json parses")
    func chatAdaptersList() throws {
        let command = try SwooshCommand.parseAsRoot(["chat-adapters", "list", "--json"])
        let list = try #require(command as? ChatAdaptersListCommand)
        #expect(list.json == true)
    }

    @Test("swoosh chat-adapters enable <id> parses")
    func chatAdaptersEnable() throws {
        let command = try SwooshCommand.parseAsRoot(["chat-adapters", "enable", "slack"])
        let enable = try #require(command as? ChatAdaptersEnableCommand)
        #expect(enable.id == "slack")
    }

    @Test("swoosh terminal backends parses")
    func terminalBackends() throws {
        let command = try SwooshCommand.parseAsRoot(["terminal", "backends"])
        #expect(command is TerminalBackendsCommand)
    }

    @Test("swoosh terminal configure docker parses with image")
    func terminalConfigure() throws {
        let command = try SwooshCommand.parseAsRoot([
            "terminal", "configure", "docker", "--docker-image", "swift:6.0",
        ])
        let cfg = try #require(command as? TerminalConfigureCommand)
        #expect(cfg.backend.rawValue == "docker")
        #expect(cfg.dockerImage == "swift:6.0")
    }
}

@Suite("Argument parsing — skills / cron / plugin / daemon / completions / self-test")
struct ExtraParsingTests {
    @Test("swoosh skills list --all --json parses")
    func skillsList() throws {
        let command = try SwooshCommand.parseAsRoot(["skills", "list", "--all", "--json"])
        let list = try #require(command as? SkillsListCommand)
        #expect(list.all == true)
        #expect(list.json == true)
    }

    @Test("swoosh skills delete <id> --force parses")
    func skillsDelete() throws {
        let command = try SwooshCommand.parseAsRoot(["skills", "delete", "my-skill", "--force"])
        let del = try #require(command as? SkillsDeleteCommand)
        #expect(del.id == "my-skill")
        #expect(del.force == true)
    }

    @Test("swoosh cron create parses required options")
    func cronCreate() throws {
        let command = try SwooshCommand.parseAsRoot([
            "cron", "create",
            "--schedule", "every 30m",
            "--prompt", "ping",
            "--name", "ping-job",
        ])
        let create = try #require(command as? CronCreateCommand)
        #expect(create.schedule == "every 30m")
        #expect(create.prompt == "ping")
        #expect(create.name == "ping-job")
    }

    @Test("swoosh cron remove <id> --force parses")
    func cronRemove() throws {
        let command = try SwooshCommand.parseAsRoot(["cron", "remove", "ping-job", "--force"])
        let remove = try #require(command as? CronRemoveCommand)
        #expect(remove.id == "ping-job")
        #expect(remove.force == true)
    }

    @Test("swoosh plugin list parses with daemon options")
    func pluginList() throws {
        let command = try SwooshCommand.parseAsRoot([
            "plugin", "list", "--host", "10.0.0.1", "--port", "9100",
        ])
        let list = try #require(command as? PluginListCommand)
        #expect(list.daemon.host == "10.0.0.1")
        #expect(list.daemon.port == 9100)
    }

    @Test("swoosh plugin install <path> --enable parses")
    func pluginInstall() throws {
        let command = try SwooshCommand.parseAsRoot([
            "plugin", "install", "/tmp/myplug", "--enable",
        ])
        let install = try #require(command as? PluginInstallCommand)
        #expect(install.path == "/tmp/myplug")
        #expect(install.enable == true)
    }

    @Test("swoosh daemon pair --port 9090 parses")
    func daemonPair() throws {
        let command = try SwooshCommand.parseAsRoot([
            "daemon", "pair", "--port", "9090",
        ])
        let pair = try #require(command as? DaemonPairCommand)
        #expect(pair.port == 9090)
        #expect(pair.host == nil)
    }

    @Test("swoosh completions <shell> --install parses")
    func completions() throws {
        let command = try SwooshCommand.parseAsRoot(["completions", "bash", "--install"])
        let c = try #require(command as? CompletionsCommand)
        #expect(c.shell == "bash")
        #expect(c.install == true)
    }

    @Test("swoosh self-test parses")
    func selfTest() throws {
        let command = try SwooshCommand.parseAsRoot(["self-test"])
        #expect(command is SelfTestCommand)
    }

    @Test("swoosh model --test parses")
    func modelTest() throws {
        let command = try SwooshCommand.parseAsRoot(["model", "--test"])
        let m = try #require(command as? ModelCommand)
        #expect(m.test == true)
    }
}

@Suite("Argument parsing — goal / manifest")
struct GoalManifestParsingTests {
    @Test("swoosh goal list --host --port parses with daemon options")
    func goalList() throws {
        let command = try SwooshCommand.parseAsRoot([
            "goal", "list", "--host", "10.0.0.1", "--port", "9100", "--json",
        ])
        let list = try #require(command as? GoalListCommand)
        #expect(list.daemon.host == "10.0.0.1")
        #expect(list.daemon.port == 9100)
        #expect(list.json == true)
    }

    @Test("swoosh goal set --statement --max-iterations parses")
    func goalSet() throws {
        let command = try SwooshCommand.parseAsRoot([
            "goal", "set",
            "--statement", "Ship the iOS app",
            "--max-iterations", "5",
        ])
        let set = try #require(command as? GoalSetCommand)
        #expect(set.statement == "Ship the iOS app")
        #expect(set.maxIterations == 5)
    }

    @Test("swoosh goal show <id> parses")
    func goalShow() throws {
        let command = try SwooshCommand.parseAsRoot(["goal", "show", "abc123"])
        let show = try #require(command as? GoalShowCommand)
        #expect(show.goalID == "abc123")
    }

    @Test("swoosh goal abandon <id> --force parses")
    func goalAbandon() throws {
        let command = try SwooshCommand.parseAsRoot([
            "goal", "abandon", "abc123", "--force",
        ])
        let abandon = try #require(command as? GoalAbandonCommand)
        #expect(abandon.goalID == "abc123")
        #expect(abandon.force == true)
    }

    @Test("swoosh goal update <id> --state parses")
    func goalUpdate() throws {
        let command = try SwooshCommand.parseAsRoot([
            "goal", "update", "abc123", "--state", "paused",
        ])
        let update = try #require(command as? GoalUpdateCommand)
        #expect(update.goalID == "abc123")
        #expect(update.state == "paused")
    }

    @Test("swoosh goal with no subcommand defaults to list")
    func goalDefaultsToList() throws {
        let command = try SwooshCommand.parseAsRoot(["goal"])
        #expect(command is GoalListCommand)
    }

    @Test("swoosh manifest history --json parses")
    func manifestHistory() throws {
        let command = try SwooshCommand.parseAsRoot(["manifest", "history", "--json"])
        let history = try #require(command as? ManifestHistoryCommand)
        #expect(history.json == true)
    }

    @Test("swoosh manifest show <id> parses")
    func manifestShow() throws {
        let command = try SwooshCommand.parseAsRoot(["manifest", "show", "abc123"])
        let show = try #require(command as? ManifestShowCommand)
        #expect(show.manifestationID == "abc123")
    }

    @Test("swoosh manifest now --reason parses")
    func manifestNow() throws {
        let command = try SwooshCommand.parseAsRoot([
            "manifest", "now", "--reason", "user-requested",
        ])
        let now = try #require(command as? ManifestNowCommand)
        #expect(now.reason == "user-requested")
    }

    @Test("swoosh manifest delete <id> --force parses")
    func manifestDelete() throws {
        let command = try SwooshCommand.parseAsRoot([
            "manifest", "delete", "abc123", "--force",
        ])
        let delete = try #require(command as? ManifestDeleteCommand)
        #expect(delete.manifestationID == "abc123")
        #expect(delete.force == true)
    }

    @Test("swoosh manifest with no subcommand defaults to history")
    func manifestDefaultsToHistory() throws {
        let command = try SwooshCommand.parseAsRoot(["manifest"])
        #expect(command is ManifestHistoryCommand)
    }
}
