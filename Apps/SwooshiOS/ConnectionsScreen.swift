// Apps/SwooshiOS/ConnectionsScreen.swift — Connections (model + knowledge + state + media)
//
// Claude-style replacement for ControlCenterView. Top-level rows in a
// clean sectioned list, each pushing to a detail screen. Daemon data
// flows through SwooshClient exactly as before — only the chrome changes.

import SwiftUI
import SwooshClient

struct ConnectionsScreen: View {
    @Environment(ClientSession.self) private var session
    @State private var providers: ProvidersResponse?
    @State private var skills: SkillsResponse?
    @State private var memories = MemoriesResponse(approved: [], pending: [])
    @State private var records: RecordsResponse?
    @State private var media: MediaGalleryResponse?
    @State private var chatAdapters: ChatAdaptersResponse?
    @State private var isLoading = false
    @State private var errorText: String?

    /// True until the very first load resolves — drives the full-bleed
    /// loading state instead of a list of "Loading…" rows.
    @State private var hasLoadedOnce = false
    @State private var errorFeedback = 0

    var body: some View {
        Group {
            if session.isPaired {
                paired
            } else {
                unpaired
            }
        }
        .navigationTitle("Connections")
        .navigationBarTitleDisplayMode(.large)
        .task(id: session.host?.absoluteString) { await loadAll() }
        .refreshable { await loadAll() }
        .sensoryFeedback(.error, trigger: errorFeedback)
    }

    // MARK: - Paired

    @ViewBuilder
    private var paired: some View {
        if !hasLoadedOnce, isLoading {
            LoadingState("Loading connections…")
        } else if !hasLoadedOnce, let errorText {
            ContentUnavailableView {
                Label("Couldn't reach swooshd", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
            } description: {
                Text(errorText)
            } actions: {
                VStack(spacing: 10) {
                    Button("Retry") { Task { await loadAll() } }
                        .buttonStyle(.borderedProminent)
                    NavigationLink(value: DrawerDestination.settings) {
                        Label("Open Pairing", systemImage: "gear")
                    }
                    .buttonStyle(.bordered)
                }
            }
        } else {
            List {
                daemonStatusSection
                modelsSection
                channelsSection
                knowledgeSection
                stateSection
                mediaSection
                if let errorText {
                    Section {
                        ErrorRow(message: errorText) { await loadAll() }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var channelsSection: some View {
        Section("Channels") {
            NavigationLink {
                ChannelsScreen()
            } label: {
                IconRow(
                    tile: IconTile(systemName: "bubble.left.and.text.bubble.right.fill", tint: .blue),
                    title: "Chat adapters",
                    detail: channelsCaption
                )
            }
        }
    }

    private var channelsCaption: String {
        guard let chatAdapters else { return "Loading…" }
        let adapters = chatAdapters.adapters
        let enabled = adapters.filter(\.enabled).count
        let configured = adapters.filter(\.configured).count
        return "\(enabled) on · \(configured) configured · \(adapters.count) total"
    }

    private var unpaired: some View {
        ContentUnavailableView {
            Label("Pair this iPhone first", systemImage: "link.badge.plus")
        } description: {
            Text("Connections needs the daemon (`swooshd`) to be running on your Mac and this iPhone paired with its bearer token.")
        } actions: {
            VStack(spacing: 10) {
                NavigationLink(value: DrawerDestination.settings) {
                    Label("Open Pairing", systemImage: "gear")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: 240)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)

                Text(pairingHowTo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    private var pairingHowTo: String {
        """
        On your Mac:
          cd /Users/home/swoosh
          SWOOSH_HOST=0.0.0.0 swift run swooshd
        Then copy the token from ~/.swoosh/api_token into iPhone Settings.
        """
    }

    // MARK: - Sections

    /// Top-of-screen "daemon is reachable" banner. Without it, users
    /// staring at the empty-by-default Models / Skills / Memories sections
    /// concluded "connections don't ever connect" — there was no signal
    /// distinguishing "daemon unreachable" from "daemon reachable but
    /// nothing configured yet."
    private var daemonStatusSection: some View {
        Section {
            HStack(spacing: 12) {
                Circle()
                    .fill(daemonStatusColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: daemonStatusColor.opacity(0.6), radius: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(daemonStatusTitle)
                        .font(.body.weight(.semibold))
                    if let host = session.host {
                        Text(host.host ?? host.absoluteString)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let active = providers?.activeProviderID {
                    Text(active)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.15), in: .capsule)
                }
            }
            if needsProviderKey {
                NavigationLink(value: DrawerDestination.settings) {
                    Label("Add a provider key on the Mac", systemImage: "key")
                        .foregroundStyle(.tint)
                }
            }
        } header: {
            Text("Daemon")
        } footer: {
            if needsProviderKey {
                Text("swooshd is reachable, but only the local diagnostic fallback is active. Real replies need a cloud API key. On the Mac: `swoosh provider auth openai --api-key sk-…` then restart swooshd.")
            } else if let active = providers?.activeProviderID {
                Text("Routing to \(providerName(id: active, in: providers!)).")
            }
        }
    }

    private var daemonStatusColor: Color {
        switch session.lastHealth {
        case .ok:          return .green
        case .unreachable: return .red
        case .unknown:     return .gray
        }
    }

    private var daemonStatusTitle: String {
        switch session.lastHealth {
        case .ok:          return "Connected to swooshd"
        case .unreachable: return "swooshd unreachable"
        case .unknown:     return "swooshd status pending…"
        }
    }

    private var needsProviderKey: Bool {
        guard let providers else { return false }
        return providers.activeProviderID == "local-diagnostic"
    }

    private var modelsSection: some View {
        Section {
            if let providers, !providers.providers.isEmpty {
                ForEach(providers.providers) { provider in
                    NavigationLink {
                        ProviderDetailScreen(provider: provider, all: providers)
                    } label: {
                        ProviderRow(provider: provider, active: provider.id == providers.activeProviderID)
                    }
                }
            } else if isLoading {
                LoadingRow("Loading providers…")
            } else {
                ContentUnavailableView {
                    Label("No models connected", systemImage: "cpu")
                } description: {
                    Text("swooshd reported no model providers. Add an API key on the Mac, then pull to refresh.")
                } actions: {
                    Button("Refresh") { Task { await loadAll() } }
                }
            }
        } header: {
            Text("Models")
        } footer: {
            if let providers, let active = providers.activeProviderID {
                Text("Active: \(providerName(id: active, in: providers))")
            }
        }
    }

    private var knowledgeSection: some View {
        Section("Knowledge") {
            NavigationLink {
                SkillsDetailScreen(skills: skills?.skills ?? [])
            } label: {
                IconRow(
                    tile: IconTile(systemName: "books.vertical.fill", tint: .indigo),
                    title: "Skills",
                    detail: skillsCaption
                )
            }
            NavigationLink {
                MemoriesDetailScreen(memories: memories)
            } label: {
                IconRow(
                    tile: IconTile(systemName: "brain.head.profile", tint: .purple),
                    title: "Memories",
                    detail: memoryCaption
                )
            }
            NavigationLink {
                MCPServersScreen()
            } label: {
                IconRow(
                    tile: IconTile(systemName: "puzzlepiece.extension.fill", tint: .cyan),
                    title: "MCP Servers",
                    detail: mcpServersCaption
                )
            }
        }
    }

    private var stateSection: some View {
        Section("Runtime") {
            NavigationLink {
                RuntimeDetailScreen(records: records, runtimeConfig: session.runtimeConfig)
            } label: {
                IconRow(
                    tile: IconTile(systemName: "gauge.with.dots.needle.50percent", tint: .teal),
                    title: "Readiness & policy",
                    detail: stateCaption
                )
            }
            NavigationLink {
                AutomationsDetailScreen(records: records)
            } label: {
                IconRow(
                    tile: IconTile(systemName: "calendar.badge.clock", tint: .orange),
                    title: "Automations & goals",
                    detail: automationsCaption
                )
            }
        }
    }

    private var mediaSection: some View {
        Section("Media") {
            NavigationLink {
                MediaDetailScreen(media: media)
            } label: {
                IconRow(
                    tile: IconTile(systemName: "photo.on.rectangle.angled", tint: .pink),
                    title: "Generated files",
                    detail: mediaCaption
                )
            }
        }
    }

    // MARK: - Captions

    private var mcpServersCaption: String {
        let count = MCPServerStore.shared.servers.count
        if count == 0 { return "Add a custom server or pick a template" }
        let enabled = MCPServerStore.shared.servers.filter(\.enabled).count
        return "\(enabled)/\(count) enabled"
    }

    private var skillsCaption: String {
        guard let count = skills?.skills.count else { return "Loading…" }
        return count == 0 ? "No promotable skills" : "\(count) promotable"
    }

    private var memoryCaption: String {
        "\(memories.approved.count) approved · \(memories.pending.count) pending"
    }

    private var stateCaption: String {
        records?.readiness.state.rawValue.capitalized ?? "Loading…"
    }

    private var automationsCaption: String {
        guard let records else { return "Loading…" }
        let cronCount = records.cronJobs.count
        let goalCount = records.goals.count
        return "\(cronCount) cron · \(goalCount) goals"
    }

    private var mediaCaption: String {
        guard let media else { return "Loading…" }
        return "\(media.items.count) items · \(media.root)"
    }

    private func providerName(id: String, in providers: ProvidersResponse) -> String {
        providers.providers.first { $0.id == id }?.name ?? id
    }

    // MARK: - Load

    private func loadAll() async {
        guard session.isPaired, let client = session.client() else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            isLoading = true
            errorText = nil
        }
        defer {
            withAnimation(.easeOut(duration: 0.22)) {
                isLoading = false
                hasLoadedOnce = true
            }
        }

        // Run every endpoint in parallel and collect per-endpoint results.
        // The old version awaited each call serially with `try`, so a
        // single 404 / network blip killed everything — the user saw a
        // generic "Couldn't reach swooshd" even when 5 of 6 endpoints
        // worked. Now individual failures degrade gracefully and we only
        // surface the *first* error encountered as a banner.
        async let providersR  = result { try await client.providers() }
        async let skillsR     = result { try await client.skills() }
        async let memoriesR   = result { try await client.memories() }
        async let recordsR    = result { try await client.records() }
        async let mediaR      = result { try await client.mediaGallery() }
        async let adaptersR   = result { try await client.chatAdapters() }

        let (p, s, m, r, md, a) = await (providersR, skillsR, memoriesR, recordsR, mediaR, adaptersR)

        var firstError: Error?
        withAnimation(.easeOut(duration: 0.22)) {
            if case .success(let v) = p { providers = v }    else if case .failure(let e) = p, firstError == nil { firstError = e }
            if case .success(let v) = s { skills = v }       else if case .failure(let e) = s, firstError == nil { firstError = e }
            if case .success(let v) = m { memories = v }     else if case .failure(let e) = m, firstError == nil { firstError = e }
            if case .success(let v) = r { records = v }      else if case .failure(let e) = r, firstError == nil { firstError = e }
            if case .success(let v) = md { media = v }       else if case .failure(let e) = md, firstError == nil { firstError = e }
            if case .success(let v) = a { chatAdapters = v } else if case .failure(let e) = a, firstError == nil { firstError = e }

            errorText = firstError.map { humanizeNetworkError($0) }
        }
        if firstError != nil { errorFeedback &+= 1 }
        await session.refresh()
    }

    /// Tiny `Result` helper so we can `async let` six fallible calls and
    /// inspect each one independently.
    private func result<T>(_ work: @Sendable () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await work()) }
        catch { return .failure(error) }
    }

    /// Turn URLSession noise into something a person can act on.
    private func humanizeNetworkError(_ error: Error) -> String {
        let raw = error.localizedDescription
        if let url = error as? URLError {
            switch url.code {
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
                return "Can't reach swooshd. Is `swift run swooshd` running on your Mac and on the same Wi-Fi as this iPhone?"
            case .timedOut:
                return "Timed out reaching swooshd. Check that the host URL in Settings → Pairing matches the Mac's IP."
            case .userAuthenticationRequired:
                return "Bearer token rejected. Re-copy `~/.swoosh/api_token` from the Mac into Settings → Pairing."
            case .notConnectedToInternet:
                return "This iPhone isn't on a network."
            default:
                return "Network error (\(url.code.rawValue)). \(raw)"
            }
        }
        return raw
    }
}

// MARK: - Reusable rows

struct IconRow: View {
    let tile: IconTile
    let title: String
    var detail: String?

    var body: some View {
        HStack(spacing: 12) {
            tile
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

private struct ProviderRow: View {
    let provider: ProviderSummary
    let active: Bool

    var body: some View {
        HStack(spacing: 12) {
            ProviderLogo(providerID: provider.id, providerName: provider.name, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(provider.name)
                        .font(.body.weight(.semibold))
                    if active {
                        Text("Active")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.18)))
                            .foregroundStyle(.green)
                    }
                }
                HStack(spacing: 6) {
                    statusPill
                    if let model = provider.model, !model.isEmpty {
                        Text(model)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusPill: some View {
        if provider.configured {
            Text("Ready")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.blue.opacity(0.15)))
                .foregroundStyle(.blue)
        } else {
            Text("Missing key")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.orange.opacity(0.18)))
                .foregroundStyle(.orange)
        }
    }
}

// MARK: - Provider detail

struct ProviderDetailScreen: View {
    @Environment(ClientSession.self) private var session
    let provider: ProviderSummary
    let all: ProvidersResponse
    @State private var draftKey: String = ""
    @State private var saving = false
    @State private var setActive = false
    @State private var message: String?
    @State private var error: String?
    @State private var successFeedback = 0
    @State private var errorFeedback = 0

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    ProviderLogo(providerID: provider.id, providerName: provider.name, size: 48, cornerRadius: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.name).font(.title3.weight(.semibold))
                        Text(provider.model ?? provider.status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Status") {
                LabeledContent("Reachable", value: provider.configured ? "Yes" : "Needs key")
                LabeledContent("Location", value: provider.location)
                LabeledContent("Cost", value: provider.cost)
                if let preferred = all.preferredProviderID {
                    LabeledContent("Preferred", value: preferred == provider.id ? "This" : "—")
                }
            }

            if acceptsPhoneKey {
                Section {
                    SecureField("Paste API key", text: $draftKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(saving ? "Saving…" : "Save key") {
                        Task { await saveKey() }
                    }
                    .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                } header: {
                    Text("API key")
                } footer: {
                    Text("Stored on swooshd in the Mac Keychain. Restart the daemon for the new key to take effect.")
                }
            }

            if provider.id == "codex" {
                CodexAuthSection(configured: provider.configured)
            }

            if selectableFromPhone {
                Section {
                    Button(saving ? "Setting…" : "Make this the preferred provider") {
                        Task { await selectProvider() }
                    }
                    .disabled(saving || all.preferredProviderID == provider.id)
                } footer: {
                    Text("The agent will route new conversations through this provider on the next daemon restart.")
                }
            }

            if let message {
                Section { Label(message, systemImage: "checkmark.circle").foregroundStyle(.green).font(.footnote) }
            }
            if let error {
                Section {
                    ErrorRow(message: error) {
                        // Retry whichever op was in flight: a draft key
                        // present means saveKey, otherwise selectProvider.
                        if !draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            await saveKey()
                        } else {
                            await selectProvider()
                        }
                    }
                }
            }
        }
        .navigationTitle(provider.name)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: successFeedback)
        .sensoryFeedback(.error, trigger: errorFeedback)
    }

    private var acceptsPhoneKey: Bool {
        // Only the providers the daemon's `saveProviderKey` accepts.
        ["openai", "openrouter"].contains(provider.id)
    }

    private var selectableFromPhone: Bool {
        // Codex auth needs the dedicated /api/codex/auth flow, not the
        // generic provider-select. Other providers can be selected here.
        provider.id != "local-diagnostic" && provider.id != "codex"
    }

    private func saveKey() async {
        guard let client = session.client() else { return }
        let key = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        saving = true
        error = nil
        message = nil
        defer { saving = false }
        do {
            let response = try await client.saveProviderKey(providerID: provider.id, apiKey: key)
            withAnimation(.easeOut(duration: 0.22)) { message = response.message }
            draftKey = ""
            successFeedback &+= 1
            await session.refresh()
        } catch {
            withAnimation(.easeOut(duration: 0.22)) { self.error = error.localizedDescription }
            errorFeedback &+= 1
        }
    }

    private func selectProvider() async {
        guard let client = session.client() else { return }
        saving = true
        error = nil
        message = nil
        defer { saving = false }
        do {
            let response = try await client.selectProvider(providerID: provider.id)
            withAnimation(.easeOut(duration: 0.22)) { message = response.message }
            successFeedback &+= 1
            await session.refresh()
        } catch {
            withAnimation(.easeOut(duration: 0.22)) { self.error = error.localizedDescription }
            errorFeedback &+= 1
        }
    }
}

private extension ProviderSummary {
    var location: String {
        switch id {
        case "local-openai", "local-diagnostic", "mlx-local", "apple-foundation": return "Local"
        default: return "Cloud"
        }
    }
    var cost: String {
        switch id {
        case "local-openai", "local-diagnostic", "mlx-local", "apple-foundation": return "Free"
        case "codex": return "ChatGPT Plus"
        default: return "Paid"
        }
    }
}

// MARK: - Skills, Memories, Runtime, Automations, Media

struct SkillsDetailScreen: View {
    let skills: [SkillSummary]
    var body: some View {
        Group {
        if skills.isEmpty {
            ContentUnavailableView {
                Label("No skills yet", systemImage: "books.vertical")
            } description: {
                Text("Reviewed and promoted skills appear here. Draft skills are reviewed on the Mac before they reach the agent.")
            }
        } else {
            List {
                ForEach(skills) { skill in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(skill.title).font(.body.weight(.semibold))
                            Spacer()
                            Text(skill.trust)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.blue.opacity(0.15)))
                                .foregroundStyle(.blue)
                        }
                        Text(skill.description).font(.footnote).foregroundStyle(.secondary)
                        Text(skill.category).font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        }
        .navigationTitle("Skills")
    }
}

struct MemoriesDetailScreen: View {
    let memories: MemoriesResponse
    @State private var bucket: Bucket = .approved
    enum Bucket: String, CaseIterable, Identifiable { case approved, pending, rejected; var id: String { rawValue } }

    var body: some View {
        List {
            Section {
                Picker("Bucket", selection: $bucket) {
                    ForEach(Bucket.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                let items: [MemorySummary] = {
                    switch bucket {
                    case .approved: return memories.approved
                    case .pending:  return memories.pending
                    case .rejected: return memories.rejected
                    }
                }()
                if items.isEmpty {
                    Text("No \(bucket.rawValue) memories.").foregroundStyle(.secondary).font(.footnote)
                } else {
                    ForEach(items) { memory in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(memory.text)
                            HStack(spacing: 8) {
                                Text(memory.category)
                                Text(memory.sensitivity)
                                if let confidence = memory.confidence {
                                    Text(confidence, format: .percent.precision(.fractionLength(0)))
                                }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .navigationTitle("Memories")
    }
}

struct RuntimeDetailScreen: View {
    let records: RecordsResponse?
    let runtimeConfig: RuntimeConfigResponse?

    var body: some View {
        List {
            if let readiness = records?.readiness {
                Section("Readiness") {
                    LabeledContent("State", value: readiness.state.rawValue.capitalized)
                    Text(readiness.summary).font(.footnote).foregroundStyle(.secondary)
                    ForEach(readiness.components) { component in
                        HStack {
                            Image(systemName: component.status.systemImage)
                                .foregroundStyle(component.status.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(component.title)
                                Text(component.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if let runtimeConfig {
                Section("Runtime config") {
                    LabeledContent("Profile", value: runtimeConfig.permissionProfile ?? "Unconfigured")
                    LabeledContent("Mode", value: runtimeConfig.setupMode ?? "Unknown")
                    if let policy = runtimeConfig.toolPolicy {
                        LabeledContent("Tool calls", value: policy.allowModelToolCalls ? "Enabled" : "Disabled")
                        LabeledContent("Max calls", value: "\(policy.maxToolCallsPerTurn)")
                    }
                }
                if !runtimeConfig.safetyFlags.isEmpty {
                    Section("Safety flags") {
                        ForEach(runtimeConfig.safetyFlags) { flag in
                            LabeledContent(flag.label) {
                                Image(systemName: flag.enabled ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(flag.enabled ? .green : .secondary)
                            }
                        }
                    }
                }
            }
            if let counters = records?.metrics.counters, !counters.isEmpty {
                Section("Counters") {
                    ForEach(counters) { counter in
                        LabeledContent(counter.id.replacingOccurrences(of: "_", with: " "), value: "\(counter.value)")
                    }
                }
            }
            // The parent passes nil until `loadAll` resolves — show a
            // loading row rather than a blank list.
            if records == nil, runtimeConfig == nil {
                LoadingRow("Loading runtime…")
            }
        }
        .navigationTitle("Readiness & policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AutomationsDetailScreen: View {
    let records: RecordsResponse?

    var body: some View {
        List {
            if let records {
                Section("Goals") {
                    if records.goals.isEmpty {
                        Text("No persistent goals.").foregroundStyle(.secondary).font(.footnote)
                    } else {
                        ForEach(records.goals) { goal in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(goal.statement)
                                HStack { Text(goal.state); Text(goal.progress) }
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Manifesting") {
                    if records.manifestations.isEmpty {
                        Text("No manifestation passes recorded.").foregroundStyle(.secondary).font(.footnote)
                    } else {
                        ForEach(records.manifestations) { manifestation in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(manifestation.summary ?? manifestation.triggerReason)
                                HStack { Text(manifestation.status); Text("\(manifestation.proposalCount) proposals") }
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Cron jobs") {
                    if records.cronJobs.isEmpty {
                        Text("No scheduled agent jobs.").foregroundStyle(.secondary).font(.footnote)
                    } else {
                        ForEach(records.cronJobs) { job in
                            HStack {
                                IconTile(systemName: job.enabled ? "play.fill" : "pause.fill", tint: job.enabled ? .green : .secondary, size: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(job.name)
                                    Text(job.state).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } else {
                LoadingRow("Loading automations…")
            }
        }
        .navigationTitle("Automations & goals")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MediaDetailScreen: View {
    let media: MediaGalleryResponse?

    var body: some View {
        List {
            if let media {
                Section("Gallery") {
                    LabeledContent("Root", value: media.root)
                    LabeledContent("Total items", value: "\(media.items.count)")
                    HStack(spacing: 12) {
                        kindStat(.image, items: media.items, tint: .green)
                        kindStat(.video, items: media.items, tint: .blue)
                        kindStat(.audio, items: media.items, tint: .purple)
                    }
                    .frame(maxWidth: .infinity)
                }
                Section("Files") {
                    if media.items.isEmpty {
                        ContentUnavailableView {
                            Label("No generated files", systemImage: "photo.on.rectangle.angled")
                        } description: {
                            Text("Images, video, and audio the agent produces land here.")
                        }
                    } else {
                        ForEach(media.items) { item in
                            HStack(spacing: 12) {
                                IconTile(systemName: item.kind.systemImage, tint: item.kind.tint, size: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.body.weight(.semibold))
                                    Text(item.relativePath).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer(minLength: 0)
                                Text(ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file))
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            } else {
                LoadingRow("Loading media…")
            }
        }
        .navigationTitle("Generated files")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func kindStat(_ kind: MediaGalleryKind, items: [MediaGalleryItem], tint: Color) -> some View {
        VStack(spacing: 6) {
            IconTile(systemName: kind.systemImage, tint: tint, size: 36, cornerRadius: 10)
            Text("\(items.filter { $0.kind == kind }.count)")
                .font(.title3.weight(.semibold))
            Text(kind.rawValue.capitalized)
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Shared extensions

private extension SwooshReadinessStatus {
    var systemImage: String {
        switch self {
        case .ready:   "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .blocked: "xmark.octagon.fill"
        }
    }
    var tint: Color {
        switch self {
        case .ready: .green
        case .warning: .orange
        case .blocked: .red
        }
    }
}

private extension MediaGalleryKind {
    var systemImage: String {
        switch self {
        case .image: "photo"
        case .video: "film"
        case .audio: "waveform"
        case .other: "doc"
        }
    }
    var tint: Color {
        switch self {
        case .image: .green
        case .video: .blue
        case .audio: .purple
        case .other: .secondary
        }
    }
}
