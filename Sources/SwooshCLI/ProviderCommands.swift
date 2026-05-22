// SwooshCLI/ProviderCommands.swift — 0.9P Provider CLI
//
// swoosh provider list
// swoosh provider auth <provider> --api-key <key>
// swoosh provider auth openrouter --pkce
// swoosh provider test [<provider>]
// swoosh provider discover

import ArgumentParser
import SwooshProviders
import SwooshProviderBridge
import SwooshModels
import SwooshSecrets
import SwooshTools
import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Provider command group
// ═══════════════════════════════════════════════════════════════════

struct ProviderCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "provider",
        abstract: "Manage model providers and API keys.",
        subcommands: [
            ProviderListCommand.self,
            ProviderAuthCommand.self,
            ProviderTestCommand.self,
            ProviderDiscoverCommand.self,
        ],
        defaultSubcommand: ProviderListCommand.self
    )
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - provider list
// ═══════════════════════════════════════════════════════════════════

struct ProviderListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List configured providers.")

    func run() async throws {
        let secrets = KeychainSecretStore()

        print("\n─── Model Providers ───────────────────────────\n")

        let providers: [(String, String, String, SecretRef)] = [
            ("OpenAI", ModelDefaults.openAIProviderID, ModelDefaults.openAIModelID, SecretRef(ModelDefaults.openAIProviderID, "api_key")),
            ("OpenRouter", ModelDefaults.openRouterProviderID, ModelDefaults.openRouterModelID, SecretRef(ModelDefaults.openRouterProviderID, "api_key")),
            ("Eliza Cloud", ModelDefaults.elizaCloudProviderID, ModelDefaults.elizaCloudModelID, SecretRef(ModelDefaults.elizaCloudProviderID, "api_key")),
        ]

        for (name, _, model, ref) in providers {
            let hasKey = (try? await secrets.exists(ref)) ?? false
            let icon = hasKey ? "\u{001B}[32m✓\u{001B}[0m" : "\u{001B}[33m○\u{001B}[0m"
            let status = hasKey ? "configured" : "not configured"
            print("  \(icon) \(name.padding(toLength: 16, withPad: " ", startingAt: 0)) \(status.padding(toLength: 18, withPad: " ", startingAt: 0)) model: \(model)")
        }

        // Check local
        print("")
        let discovery = LocalProviderDiscovery()
        let found = await discovery.discover()
        if found.isEmpty {
            print("  \u{001B}[33m○\u{001B}[0m Local            no local server detected")
        } else {
            for provider in found {
                let models = provider.models.prefix(3).joined(separator: ", ")
                let suffix = provider.models.count > 3 ? " +\(provider.models.count - 3) more" : ""
                print("  \u{001B}[32m✓\u{001B}[0m \(provider.name.padding(toLength: 16, withPad: " ", startingAt: 0)) running          models: \(models)\(suffix)")
            }
        }

        print("\n  Use `swoosh provider auth <name> --api-key <key>` to configure.")
        print("  Use `swoosh provider test` to verify.\n")
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - provider auth
// ═══════════════════════════════════════════════════════════════════

struct ProviderAuthCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "auth", abstract: "Store API key for a provider.")

    @Argument(help: "Provider name: openai, openrouter, eliza-cloud")
    var provider: String

    @Option(name: .long, help: "API key (stored in Keychain, never logged)")
    var apiKey: String?

    @Flag(name: .long, help: "Use OpenRouter PKCE flow (opens browser)")
    var pkce = false

    func run() async throws {
        let secrets = KeychainSecretStore()

        if pkce && provider == "openrouter" {
            // PKCE flow
            let auth = OpenRouterPKCEAuth(secrets: secrets)
            let (url, _) = await auth.buildAuthURL()

            print("\n─── OpenRouter PKCE Auth ───────────────────────\n")
            print("  1. Open this URL in your browser:\n")
            print("     \(url)\n")
            print("  2. Authorize Swoosh on OpenRouter")
            print("  3. Copy the code from the callback URL")
            print("  4. Paste it below:\n")

            print("  Code: ", terminator: "")
            guard let code = readLine()?.trimmingCharacters(in: .whitespaces), !code.isEmpty else {
                print("  \u{001B}[31m✗\u{001B}[0m No code provided.")
                return
            }

            let health = try await auth.exchangeCode(code)
            print("\n  \u{001B}[32m✓\u{001B}[0m \(health.message ?? "API key stored in Keychain")\n")
            return
        }

        // Direct API key
        guard let key = apiKey else {
            // Interactive mode: ask for key
            print("\n  Enter API key for \(provider): ", terminator: "")
            guard let inputKey = readLine()?.trimmingCharacters(in: .whitespaces), !inputKey.isEmpty else {
                print("  \u{001B}[31m✗\u{001B}[0m No key provided.")
                return
            }
            try await secrets.set(inputKey, ref: SecretRef(provider, "api_key"))
            print("  \u{001B}[32m✓\u{001B}[0m API key for \(provider) stored in Keychain.\n")
            return
        }

        // Store the provided key
        try await secrets.set(key, ref: SecretRef(provider, "api_key"))
        print("\n  \u{001B}[32m✓\u{001B}[0m API key for \(provider) stored in Keychain.")
        print("  Key is never logged, stored only in macOS Keychain.\n")
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - provider test
// ═══════════════════════════════════════════════════════════════════

struct ProviderTestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "test", abstract: "Test provider connectivity.")

    @Argument(help: "Provider to test (omit to test all configured)")
    var provider: String?

    func run() async throws {
        try await runProviderTests(provider: provider)
    }
}

func runProviderTests(provider: String?) async throws {
    let secrets = KeychainSecretStore()
    print("\n─── Provider Test ─────────────────────────────\n")

    let providersToTest: [(String, SecretRef)] = {
        if let provider {
            return [(provider, SecretRef(provider, "api_key"))]
        }
        return [
            ("openai", SecretRef("openai", "api_key")),
            ("openrouter", SecretRef("openrouter", "api_key")),
            ("eliza-cloud", SecretRef("eliza-cloud", "api_key")),
        ]
    }()

    for (name, ref) in providersToTest {
        let hasKey = (try? await secrets.exists(ref)) ?? false
        if !hasKey {
            print("  \u{001B}[33m○\u{001B}[0m \(name): no API key configured")
            continue
        }

        print("  \u{001B}[36m⟳\u{001B}[0m \(name): testing...", terminator: "")
        fflush(stdout)

        let start = Date()
        do {
            let testMessages: [ChatMessage] = [
                ChatMessage(role: .user, content: "Say 'ok' and nothing else.")
            ]
            let testRequest = ModelRequest(
                model: UnifiedModelCatalog.defaultModel(providerID: name) ?? ModelDefaults.openAIModelID,
                messages: testMessages
            )

            let (router, _) = await ProviderFactory.buildRouter(secrets: secrets)
            let response = try await router.completeWith(providerID: ProviderID(name), request: testRequest)

            let latency = Int(Date().timeIntervalSince(start) * 1000)
            let preview = response.text.prefix(40).replacingOccurrences(of: "\n", with: " ")
            print("\r  \u{001B}[32m✓\u{001B}[0m \(name): healthy (\(latency)ms) — \"\(preview)\"")
        } catch {
            let errMsg = "\(error)".prefix(60)
            let suggestion = suggestFix(for: error, provider: name)
            print("\r  \u{001B}[31m✗\u{001B}[0m \(name): \(errMsg)")
            if let suggestion = suggestion {
                print("    \u{001B}[33m→\u{001B}[0m \(suggestion)")
            }
        }
    }

    print("")
    let discovery = LocalProviderDiscovery()
    let found = await discovery.discover()
    if found.isEmpty {
        print("  \u{001B}[33m○\u{001B}[0m local: no server detected at common ports")
    } else {
        for local in found {
            print("  \u{001B}[32m✓\u{001B}[0m \(local.name): \(local.models.count) model(s) available")
        }
    }
}

// MARK: - Error Suggestions

private func suggestFix(for error: Error, provider: String) -> String? {
    let errorDesc = "\(error)".lowercased()

    if errorDesc.contains("api key") || errorDesc.contains("unauthorized") || errorDesc.contains("401") {
        switch provider {
        case "openai":
            return "Run: swoosh provider auth openai --api-key <key>"
        case "openrouter":
            return "Run: swoosh provider auth openrouter (opens browser for PKCE flow)"
        case "eliza-cloud":
            return "Run: swoosh provider auth eliza-cloud --api-key <key>"
        default:
            return "Run: swoosh provider auth \(provider) --api-key <key>"
        }
    }

    if errorDesc.contains("network") || errorDesc.contains("connection") || errorDesc.contains("timeout") {
        return "Check your internet connection and try again"
    }

    if errorDesc.contains("rate limit") || errorDesc.contains("429") {
        return "Rate limited. Wait a moment and retry"
    }

    if errorDesc.contains("quota") || errorDesc.contains("credit") {
        return "Check your account quota/billing at the provider's dashboard"
    }

    if errorDesc.contains("model") || errorDesc.contains("not found") {
        return "The model may not be available. Try: swoosh provider list"
    }

    return "Run: swoosh doctor for diagnostics"
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - provider discover
// ═══════════════════════════════════════════════════════════════════

struct ProviderDiscoverCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "discover", abstract: "Discover local inference servers.")

    func run() async throws {
        print("\n─── Local Provider Discovery ──────────────────\n")
        print("  Probing common ports...\n")

        let discovery = LocalProviderDiscovery()
        let found = await discovery.discover()

        if found.isEmpty {
            print("  No local inference servers found.")
            print("")
            print("  Supported servers:")
            print("    • Ollama    — http://127.0.0.1:11434")
            print("    • LM Studio — http://127.0.0.1:1234")
            print("    • vLLM      — http://127.0.0.1:8000")
            print("    • llama.cpp — http://127.0.0.1:8080")
            print("")
            return
        }

        for provider in found {
            print("  \u{001B}[32m✓\u{001B}[0m \(provider.name) at \(provider.baseURL)")
            print("    Models:")
            for model in provider.models {
                print("      • \(model)")
            }
            print("")
        }
    }
}
