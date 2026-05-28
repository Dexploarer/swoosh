// SwooshProviderBridge/ProviderFactory+Config.swift — 0.1A Config-driven provider construction
//
// Turns ProviderConfig (data from ~/.swoosh/providers.json) into live
// router state: construct provider instances for config-defined entries,
// and merge their routes over the built-in table. Kept in its own file so
// ProviderFactory.swift stays within the LOC ceiling.
//
// Honest scope: config defines new INSTANCES of existing ProviderKinds
// (another OpenAI-/Anthropic-compatible endpoint, a localhost proxy).
// Built-in providers keep their identity — a config entry whose id
// collides with a built-in is treated as routes/active only, not a
// re-registration. Brand-new provider *kinds* still need Swift.

import Foundation
#if canImport(SwooshMLX)
import SwooshMLX
#endif
import SwooshModels
import SwooshProviders
import SwooshSecrets
import SwooshTools

extension ProviderFactory {

    /// Construct a concrete provider for a config entry's kind. Returns
    /// nil for kinds that can't be built from config alone (`mlx` needs
    /// the SwooshMLX module + hardware). For `localOpenAICompatible` the
    /// resolved `apiKey` is sent as Bearer; the dedicated cloud kinds
    /// resolve their own key from their fixed Keychain namespace.
    static func makeProvider(
        kind: ProviderKind,
        baseURL: String?,
        apiKey: String?,
        providerID: ProviderID,
        displayName: String,
        secrets: any SecretStoring
    ) -> (any ModelProviding)? {
        switch kind {
        case .openAI:
            return OpenAIResponsesProvider(secrets: secrets, baseURL: baseURL ?? "https://api.openai.com")
        case .anthropic:
            return AnthropicProvider(secrets: secrets, baseURL: baseURL ?? "https://api.anthropic.com")
        case .openRouter:
            return OpenRouterProvider(secrets: secrets, baseURL: baseURL ?? "https://openrouter.ai/api/v1")
        case .detourCloud:
            return DetourCloudProvider(secrets: secrets, baseURL: baseURL ?? "https://elizacloud.ai/api/v1")
        case .localOpenAICompatible:
            return LocalOpenAICompatibleProvider(
                baseURL: baseURL ?? "http://127.0.0.1:11434/v1",
                providerID: providerID, displayName: displayName, apiKey: apiKey
            )
        case .codexCLI:
            return CodexBridgeProvider()
        case .mlx:
            return nil
        }
    }

    /// Register config-defined providers that aren't already built in.
    /// Built-in ids win identity (the config can still override their
    /// routes / mark them active).
    static func registerConfigProviders(
        _ registry: ProviderRegistry,
        config: ProviderConfig,
        secrets: any SecretStoring
    ) async {
        let builtinIDs = Set(await registry.allProviderIDs().map(\.rawValue))
        for entry in config.enabledValidProviders {
            guard !builtinIDs.contains(entry.id),
                  let kind = ProviderKind(rawValue: entry.kind) else { continue }

            let apiKey = await resolveKey(entry.secretRef, secrets: secrets)
            guard let provider = makeProvider(
                kind: kind, baseURL: entry.baseURL, apiKey: apiKey,
                providerID: ProviderID(entry.id), displayName: entry.displayName,
                secrets: secrets
            ) else { continue }

            let auth: ProviderAuthKind = entry.secretRef != nil
                ? .apiKey(namespace: entry.id, key: "api_key") : .none
            let profile = ProviderProfile(
                id: ProviderID(entry.id), kind: kind, displayName: entry.displayName,
                baseURL: entry.baseURL, auth: auth,
                defaultModel: entry.defaultModel, enabled: true,
                priority: entry.priority ?? 64
            )
            await registry.register(provider, profile: profile)
        }
    }

    /// Merge config route overrides + per-entry per-role models over the
    /// built-in route table. Both honor the preferred-provider boost.
    static func applyConfigRoutes(
        _ registry: ProviderRegistry,
        config: ProviderConfig,
        preferredProviderID: String?
    ) async {
        for override in config.routeOverrides {
            guard let role = SwooshProviders.ModelRole(rawValue: override.role) else { continue }
            await registry.addRoute(ProviderRoute(
                role: role, providerID: ProviderID(override.providerID), model: override.model,
                priority: priority(for: override.providerID,
                                   defaultPriority: override.priority,
                                   preferredProviderID: preferredProviderID)
            ))
        }
        for entry in config.enabledValidProviders {
            guard let models = entry.models else { continue }
            for (roleRaw, model) in models {
                guard let role = SwooshProviders.ModelRole(rawValue: roleRaw) else { continue }
                await registry.addRoute(ProviderRoute(
                    role: role, providerID: ProviderID(entry.id), model: model,
                    priority: priority(for: entry.id,
                                       defaultPriority: entry.priority ?? 64,
                                       preferredProviderID: preferredProviderID)
                ))
            }
        }
    }

    /// All text roles — used by live switching to point every text query
    /// at the newly-selected provider via route overrides.
    public static var textRoles: [SwooshProviders.ModelRole] {
        [.primaryChat, .coding, .fastLocal, .memoryExtraction,
         .summarization, .workflowPlanning, .toolCallRepair]
    }

    /// Resolve a `namespace.key` secret ref through the store. Returns nil
    /// when absent — the provider then sends no auth.
    private static func resolveKey(_ ref: String?, secrets: any SecretStoring) async -> String? {
        guard let ref else { return nil }
        let parts = ref.split(separator: ".", maxSplits: 1).map(String.init)
        let secretRef = parts.count == 2 ? SecretRef(parts[0], parts[1]) : SecretRef("default", ref)
        return try? await secrets.get(secretRef)
    }
}
