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
    @State private var isLoading = false
    @State private var errorText: String?

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
    }

    // MARK: - Paired

    private var paired: some View {
        List {
            modelsSection
            knowledgeSection
            stateSection
            mediaSection
            if let errorText {
                Section {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var unpaired: some View {
        ContentUnavailableView {
            Label("Pair this iPhone first", systemImage: "link.badge.plus")
        } description: {
            Text("Open Settings → Pairing and paste the bearer token from swooshd to load Connections.")
        }
    }

    // MARK: - Sections

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
                HStack {
                    ProgressView()
                    Text("Loading providers…").foregroundStyle(.secondary)
                }
            } else {
                Text("No providers reported by the daemon.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            providers = try await client.providers()
            skills = try await client.skills()
            memories = try await client.memories()
            records = try await client.records()
            media = try await client.mediaGallery()
            await session.refresh()
        } catch {
            errorText = error.localizedDescription
        }
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
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.footnote) }
            }
        }
        .navigationTitle(provider.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var acceptsPhoneKey: Bool {
        ["openai", "openrouter", "eliza-cloud", "anthropic", "google"].contains(provider.id)
    }

    private var selectableFromPhone: Bool { provider.id != "local-diagnostic" }

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
            message = response.message
            draftKey = ""
            await session.refresh()
        } catch {
            self.error = error.localizedDescription
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
            message = response.message
            await session.refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private extension ProviderSummary {
    var location: String { id == "local-openai" || id == "local-diagnostic" ? "Local" : "Cloud" }
    var cost: String { id == "local-openai" || id == "local-diagnostic" ? "Free" : "Paid" }
}

// MARK: - Skills, Memories, Runtime, Automations, Media

struct SkillsDetailScreen: View {
    let skills: [SkillSummary]
    var body: some View {
        List {
            if skills.isEmpty {
                Text("No reviewed or promoted skills loaded.")
                    .foregroundStyle(.secondary)
            } else {
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
                Text("Loading…").foregroundStyle(.secondary)
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
                        Text("No generated files yet.").foregroundStyle(.secondary).font(.footnote)
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
                Text("Loading…").foregroundStyle(.secondary)
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
