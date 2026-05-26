// DetourHomeSettingsPanel.swift — in-app Detour configuration surface (0.5A)

import SwiftUI

struct DetourHomeSettingsPanel: View {
    @ObservedObject var store: OnboardingStore
    let scan: () -> Void
    let applySetup: () -> Void
    let reviewSetup: () -> Void
    @State private var tab = DetourSettingsTab.providers
    @State private var userName = ""
    @State private var agentName = ""
    @State private var wakeWord = ""
    @State private var host = ""
    @State private var voiceEnabled = false
    @State private var consent = DetourCredentialInheritanceConsent()
    @State private var status = ""
    @State private var providerStatus = ""
    @State private var providerSummaries: [ProviderSummary] = []
    @State private var selectedProviderID = ModelDefaults.routerProviderID
    @State private var selectedModelID = ModelDefaults.routerModelID
    @State private var busyModelID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(.white.opacity(0.14))
            HStack(spacing: 0) {
                sidebar
                Divider().overlay(.white.opacity(0.14))
                ScrollView {
                    tabContent
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            footer
        }
        .frame(minHeight: 520)
        .detourLiquidGlass(cornerRadius: 22)
        .onAppear(perform: syncDrafts)
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.title.weight(.semibold))
            Spacer()
            Button("Save", action: save)
                .buttonStyle(.borderedProminent)
        }
        .padding(22)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(DetourSettingsTab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    Label(item.title, systemImage: item.systemImage)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(tab == item ? .white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(tab == item ? .white : .white.opacity(0.68))
            }
            Spacer()
        }
        .padding(16)
        .frame(width: 178)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .providers:
            providers
        case .agent:
            agent
        case .connectors:
            connectors
        case .voice:
            voice
        case .wallets:
            wallets
        case .privacy:
            privacy
        case .runtime:
            runtime
        }
    }

    private var providers: some View {
        settingsStack("Model") {
            DetourModelSelectionView(
                providers: providerSummaries,
                selectedProviderID: selectedProviderID,
                selectedModelID: selectedModelID,
                busyModelID: busyModelID,
                status: providerStatus,
                hasSignal: has,
                select: selectModel,
                refresh: refreshProviders
            )
        }
    }

    private var agent: some View {
        settingsStack("Agent") {
            settingsField("Your name", text: $userName)
            settingsField("Agent name", text: $agentName)
            HStack {
                Button("Review setup", action: reviewSetup)
                Button("Apply checks", action: applySetup)
            }
            .buttonStyle(.bordered)
        }
    }

    private var connectors: some View {
        settingsStack("Apps") {
            DetourIntegrationCatalogView(
                store: store,
                scan: scan,
                test: applySetup
            )
        }
    }

    private var voice: some View {
        settingsStack("Voice") {
            Toggle("Voice recognition", isOn: $voiceEnabled)
            settingsField("Wake word", text: $wakeWord)
            providerCard("OmniVoice", "Local", "waveform", true)
        }
    }

    private var wallets: some View {
        settingsStack("Wallets") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 164), spacing: 10)], spacing: 10) {
                providerCard("Solana", "Jupiter", "sun.max", has("solana") || has("jupiter"))
                providerCard("BNB", "BSC", "hexagon", has("bnb") || has("bsc"))
                providerCard("EVM", "Base", "network", has("evm") || has("base"))
                providerCard("Hyperliquid", "Perps", "chart.line.uptrend.xyaxis", has("hyperliquid"))
            }
        }
    }

    private var privacy: some View {
        settingsStack("Access") {
            Toggle("Keychain credentials", isOn: consentBinding(\.keychainCredentials))
            Toggle("Browser sessions", isOn: consentBinding(\.browserCookies))
            Toggle("App usage", isOn: consentBinding(\.appUsage))
            Toggle("Git history", isOn: consentBinding(\.gitHistory))
            Toggle("Contacts", isOn: consentBinding(\.contacts))
            Toggle("Messages", isOn: consentBinding(\.messages))
            Toggle("Account delegation", isOn: consentBinding(\.accountDelegation))
        }
    }

    private var runtime: some View {
        settingsStack("Runtime") {
            settingsField("Mac daemon URL", text: $host)
            HStack {
                Text("Bearer token")
                Spacer()
                Text((TokenStore.load() ?? "").isEmpty ? "Missing" : "Saved in Keychain")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Use local daemon") {
                    host = "http://127.0.0.1:8787"
                    saveHost()
                }
                Button("Save runtime", action: saveHost)
            }
            .buttonStyle(.bordered)
        }
    }

    private var footer: some View {
        HStack {
            Text(status.isEmpty ? "Saved locally." : status)
                .foregroundStyle(.secondary)
            Spacer()
            Button("All setup", action: reviewSetup)
                .buttonStyle(.bordered)
        }
        .padding(18)
    }

    private func settingsStack<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 0.98, green: 0.72, blue: 0.38))
            content()
        }
    }

    private func providerCard(_ title: String, _ subtitle: String, _ icon: String, _ active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                Spacer()
                Circle().fill(active ? .green : .red.opacity(0.65)).frame(width: 9, height: 9)
            }
            Text(title).font(.headline).lineLimit(1)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(active ? 0.24 : 0.12), lineWidth: 1)
        }
    }

    private func settingsField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
                .frame(width: 130, alignment: .leading)
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func consentBinding(_ keyPath: WritableKeyPath<DetourCredentialInheritanceConsent, Bool>) -> Binding<Bool> {
        Binding {
            consent[keyPath: keyPath]
        } set: {
            consent[keyPath: keyPath] = $0
        }
    }

    private func has(_ needle: String) -> Bool {
        store.setupInsightSnapshot.sections
            .flatMap(\.items)
            .contains { item in
                [item.id, item.title, item.subtitle ?? "", item.detail, item.sourceLabel ?? ""]
                    .joined(separator: " ")
                    .localizedCaseInsensitiveContains(needle)
            }
    }

    private func syncDrafts() {
        userName = store.userName
        agentName = store.agentName.isEmpty ? OnboardingStore.defaultAgentName : store.agentName
        wakeWord = store.voiceRecognition.wakeWord
        voiceEnabled = store.voiceRecognition.enabled
        consent = store.credentialInheritanceConsent
        host = HostStore.current?.absoluteString ?? "http://127.0.0.1:8787"
        let option = DetourModelOption.defaultOption(
            providerID: store.config.preferredProviderID,
            modelID: store.config.preferredModelID
        )
        selectedProviderID = option.providerID
        selectedModelID = option.modelID
        refreshProviders()
    }

    private func save() {
        store.saveHomeConfiguration(
            userName: userName,
            agentName: agentName,
            wakeWord: wakeWord,
            voiceRecognitionEnabled: voiceEnabled,
            credentialConsent: consent
        )
        saveHost()
    }

    private func saveHost() {
        if let url = URL(string: host.trimmingCharacters(in: .whitespacesAndNewlines)) {
            HostStore.current = url
            status = "Saved."
        } else {
            status = "Enter a valid daemon URL."
        }
    }

    private func refreshProviders() {
        Task { @MainActor in
            do {
                providerSummaries = try await DetourHomeDaemonClient.makeEnsuringDaemon().providers().providers
                if providerStatus.isEmpty {
                    providerStatus = "Runtime checked."
                }
            } catch {
                providerStatus = DetourHomeDaemonClient.display(error)
            }
        }
    }

    private func selectModel(_ option: DetourModelOption) {
        selectedProviderID = option.providerID
        selectedModelID = option.modelID
        busyModelID = option.id
        providerStatus = "Saving \(option.title)..."
        store.saveHomeModelSelection(providerID: option.providerID, modelID: option.modelID)
        Task { @MainActor in
            do {
                let response = try await DetourHomeDaemonClient.makeEnsuringDaemon().selectProvider(
                    providerID: option.providerID,
                    modelID: option.modelID
                )
                providerSummaries = response.providers
                providerStatus = response.requiresRestart
                    ? "Saved. Restart swooshd to use it."
                    : response.message
            } catch {
                providerStatus = DetourHomeDaemonClient.display(error)
            }
            busyModelID = nil
        }
    }
}

private enum DetourSettingsTab: String, CaseIterable, Identifiable {
    case providers
    case agent
    case connectors
    case voice
    case wallets
    case privacy
    case runtime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .providers: "Models"
        case .agent: "Agent"
        case .connectors: "Connectors"
        case .voice: "Voice"
        case .wallets: "Wallets"
        case .privacy: "Privacy"
        case .runtime: "Runtime"
        }
    }

    var systemImage: String {
        switch self {
        case .providers: "cloud"
        case .agent: "gearshape"
        case .connectors: "point.3.connected.trianglepath.dotted"
        case .voice: "speaker.wave.2"
        case .wallets: "wallet.pass"
        case .privacy: "lock.shield"
        case .runtime: "server.rack"
        }
    }
}
