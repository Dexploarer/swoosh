// SwooshWidgets/AppIntents/SwooshAppIntents.swift — Siri, Shortcuts, Spotlight
//
// Exposes Swoosh actions to:
// - Siri: "Hey Siri, check my AI provider status"
// - Shortcuts app: Automate Swoosh workflows
// - Spotlight: Search for providers, workflows, board cards
// - Action button: Quick access to common operations
//
// Uses AppIntents framework (macOS 13+ / iOS 16+).

import AppIntents
import SwiftUI
import Foundation
import SwooshSecrets

// ═══════════════════════════════════════════════════════════════════
// MARK: - Check provider status
// ═══════════════════════════════════════════════════════════════════

public struct CheckProviderStatusIntent: AppIntent {
    public static let title: LocalizedStringResource = "Check AI Provider Status"
    public static let description = IntentDescription(
        "Shows the status of your AI provider credentials and usage.",
        categoryName: "Status"
    )
    public static let openAppWhenRun = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let discovered = CredentialScavenger.discoverAll()

        if discovered.isEmpty {
            return .result(
                dialog: "No AI provider credentials found. Set API keys in environment variables or config files."
            ) {
                ProviderStatusSnippet(providers: [])
            }
        }

        let summary = discovered.map { "\($0.provider.displayName): ✅ \($0.source.rawValue)" }
            .joined(separator: "\n")

        return .result(
            dialog: "Found \(discovered.count) providers:\n\(summary)"
        ) {
            ProviderStatusSnippet(providers: discovered.map { cred in
                SnippetProvider(name: cred.provider.displayName,
                                source: cred.source.rawValue,
                                isHealthy: true)
            })
        }
    }
}

/// Interactive SwiftUI snippet shown in Siri/Shortcuts/Spotlight results.
struct ProviderStatusSnippet: View {
    let providers: [SnippetProvider]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.cyan)
                Text("Swoosh Providers")
                    .font(.headline)
            }

            if providers.isEmpty {
                Text("No providers configured")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(providers) { provider in
                    HStack {
                        Circle()
                            .fill(provider.isHealthy ? .green : .red)
                            .frame(width: 6, height: 6)
                        Text(provider.name)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text(provider.source)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
    }
}

struct SnippetProvider: Identifiable {
    let id = UUID()
    let name: String
    let source: String
    let isHealthy: Bool
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Discover credentials
// ═══════════════════════════════════════════════════════════════════

public struct DiscoverCredentialsIntent: AppIntent {
    public static let title: LocalizedStringResource = "Discover AI Credentials"
    public static let description = IntentDescription(
        "Scans environment, config files, and Keychain for AI provider API keys.",
        categoryName: "Credentials"
    )
    public static let openAppWhenRun = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let discovered = CredentialScavenger.discoverAll()
        let browsers = KeychainScavenger.accessibleBrowsers()

        var message = "Found \(discovered.count) credentials"
        if !browsers.isEmpty {
            message += " and \(browsers.count) browser(s) for cookie extraction"
        }
        message += "."

        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Import credentials
// ═══════════════════════════════════════════════════════════════════

public struct ImportCredentialsIntent: AppIntent {
    public static let title: LocalizedStringResource = "Import AI Credentials to Swoosh"
    public static let description = IntentDescription(
        "Imports discovered AI provider credentials into Swoosh's secure Keychain store.",
        categoryName: "Credentials"
    )
    public static let openAppWhenRun = false

    @Parameter(title: "Overwrite existing")
    public var overwrite: Bool

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = KeychainSecretStore()
        let imported = try await CredentialScavenger.importAll(into: store, overwrite: overwrite)

        if imported.isEmpty {
            return .result(dialog: "All credentials are already imported.")
        }

        let names = imported.map(\.displayName).joined(separator: ", ")
        return .result(dialog: IntentDialog(stringLiteral: "Imported \(imported.count) credentials: \(names)"))
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Shortcuts provider (exposes all intents)
// ═══════════════════════════════════════════════════════════════════

public struct SwooshShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckProviderStatusIntent(),
            phrases: [
                "Check my \(.applicationName) providers",
                "Show \(.applicationName) status",
                "What AI providers do I have in \(.applicationName)",
            ],
            shortTitle: "Provider Status",
            systemImageName: "sparkles"
        )

        AppShortcut(
            intent: DiscoverCredentialsIntent(),
            phrases: [
                "Discover AI credentials with \(.applicationName)",
                "Scan for API keys with \(.applicationName)",
            ],
            shortTitle: "Discover Credentials",
            systemImageName: "magnifyingglass"
        )

        AppShortcut(
            intent: ImportCredentialsIntent(),
            phrases: [
                "Import credentials into \(.applicationName)",
            ],
            shortTitle: "Import Credentials",
            systemImageName: "square.and.arrow.down"
        )
    }
}
