// Apps/SwooshiOS/ControlCenterView.swift — iPhone control surface for swooshd
//
// Authenticated daemon panels for providers, skills, memories, durable state,
// and generated media inventory. The phone stays a client: all data comes
// from SwooshClient wire APIs.

import SwiftUI
import SwooshClient

struct ControlCenterView: View {
    @Environment(ClientSession.self) private var session
    @State private var selectedSection: ControlSection = .providers
    @State private var providers: ProvidersResponse?
    @State private var skills: SkillsResponse?
    @State private var memories = MemoriesResponse(approved: [], pending: [])
    @State private var records: RecordsResponse?
    @State private var media: MediaGalleryResponse?
    @State private var keyDrafts: [String: String] = [:]
    @State private var selectedProviderID: String = ""
    @State private var statusMessage: String?
    @State private var errorText: String?
    @State private var isLoading = false
    @State private var isSavingProvider = false
    @State private var selectedMemoryStatus: MemoryStatus = .approved

    var body: some View {
        Group {
            if session.isPaired {
                paired
            } else {
                unpaired
            }
        }
        .task(id: session.host?.absoluteString) {
            await loadAll()
        }
        .refreshable {
            await loadAll()
        }
    }

    private var paired: some View {
        Form {
            Section {
                Picker("Section", selection: $selectedSection) {
                    ForEach(ControlSection.allCases) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(section)
                    }
                }
                .pickerStyle(.segmented)
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Refreshing daemon state")
                            .foregroundStyle(.secondary)
                    }
                }
                if let statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            switch selectedSection {
            case .providers:
                providerSections
            case .knowledge:
                knowledgeSections
            case .state:
                stateSections
            case .media:
                mediaSections
            }
        }
        .toolbar {
            Button {
                Task { await loadAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(isLoading)
        }
    }

    private var unpaired: some View {
        ContentUnavailableView {
            Label("Not paired", systemImage: "link.badge.plus")
        } description: {
            Text("Pair this phone with swooshd in Settings before opening the control surface.")
        }
    }

    private var providerSections: some View {
        Group {
            Section("Model routing") {
                if let providers {
                    Picker("Preferred", selection: $selectedProviderID) {
                        ForEach(providers.providers.filter(\.isSelectableFromPhone)) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    Button {
                        Task { await selectProvider() }
                    } label: {
                        HStack {
                            Text("Save provider preference")
                            Spacer()
                            if isSavingProvider { ProgressView() }
                        }
                    }
                    .disabled(selectedProviderID.isEmpty || isSavingProvider)
                    if let preferred = providers.preferredProviderID {
                        LabeledContent("Preferred", value: providerName(id: preferred))
                            .foregroundStyle(.secondary)
                    }
                    if let active = providers.activeProviderID {
                        LabeledContent("Active now", value: providerName(id: active))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    placeholder("Provider status has not loaded.")
                }
            }

            if let providers {
                Section("Providers") {
                    ForEach(providers.providers) { provider in
                        ProviderRow(provider: provider)
                    }
                }

                Section("API keys") {
                    ForEach(providers.providers.filter(\.acceptsPhoneKey)) { provider in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(provider.name, systemImage: provider.iconName)
                                Spacer()
                                Text(provider.configured ? "Configured" : "Missing key")
                                    .font(.caption)
                                    .foregroundStyle(provider.configured ? .green : .secondary)
                            }
                            SecureField("Paste API key", text: keyBinding(for: provider.id))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button {
                                Task { await saveProviderKey(provider.id) }
                            } label: {
                                HStack {
                                    Text("Save \(provider.shortName) key")
                                    Spacer()
                                    Image(systemName: "key")
                                }
                            }
                            .disabled((keyDrafts[provider.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingProvider)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var knowledgeSections: some View {
        Group {
            Section("Skills") {
                if let skills, !skills.skills.isEmpty {
                    ForEach(skills.skills) { skill in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(skill.title)
                                    .font(.headline)
                                Spacer()
                                Text(skill.trust)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(skill.description)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(skill.category)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    placeholder("No reviewed or promoted skills are loaded.")
                }
            }

            Section("Memories") {
                Picker("Status", selection: $selectedMemoryStatus) {
                    ForEach(MemoryStatus.allCases) { status in
                        Text(status.title).tag(status)
                    }
                }
                .pickerStyle(.segmented)

                let visible = memoryItems(for: selectedMemoryStatus)
                if visible.isEmpty {
                    placeholder("No \(selectedMemoryStatus.title.lowercased()) memories.")
                } else {
                    ForEach(visible) { memory in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(memory.text)
                                .font(.body)
                            HStack {
                                Text(memory.category)
                                Text(memory.sensitivity)
                                if let confidence = memory.confidence {
                                    Text(confidence, format: .percent.precision(.fractionLength(0)))
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var stateSections: some View {
        Group {
            Section("Readiness") {
                if let records {
                    LabeledContent("State", value: records.readiness.state.rawValue)
                    Text(records.readiness.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(records.readiness.components) { component in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label(component.title, systemImage: component.status.systemImage)
                                Spacer()
                                Text(component.status.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(component.status.tint)
                            }
                            Text(component.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    placeholder("Runtime records have not loaded.")
                }
            }

            if let config = session.runtimeConfig {
                Section("Runtime config") {
                    LabeledContent("Profile", value: config.permissionProfile ?? "Unconfigured")
                    LabeledContent("Mode", value: config.setupMode ?? "Unknown")
                    if let preferred = config.preferredProviderID {
                        LabeledContent("Preferred provider", value: preferred)
                    }
                    if let policy = config.toolPolicy {
                        LabeledContent("Tool calls", value: policy.allowModelToolCalls ? "Enabled" : "Disabled")
                        LabeledContent("Max calls", value: "\(policy.maxToolCallsPerTurn)")
                        LabeledContent("Chain depth", value: "\(policy.maxToolChainDepth)")
                    }
                }
                if !config.safetyFlags.isEmpty {
                    Section("Safety flags") {
                        ForEach(config.safetyFlags) { flag in
                            LabeledContent(flag.label) {
                                Image(systemName: flag.enabled ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(flag.enabled ? .green : .secondary)
                            }
                        }
                    }
                }
            }

            if let records {
                Section("Counters") {
                    ForEach(records.metrics.counters) { counter in
                        LabeledContent(counter.id.replacingOccurrences(of: "_", with: " "), value: "\(counter.value)")
                    }
                }
                Section("Board") {
                    if records.boardCards.isEmpty {
                        placeholder("No board cards.")
                    } else {
                        ForEach(records.boardCards) { card in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(card.title)
                                    .font(.headline)
                                Text(card.detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Goals") {
                    if records.goals.isEmpty {
                        placeholder("No persistent goals.")
                    } else {
                        ForEach(records.goals) { goal in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(goal.statement)
                                HStack {
                                    Text(goal.state)
                                    Text(goal.progress)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Manifesting") {
                    if records.manifestations.isEmpty {
                        placeholder("No manifestation passes recorded.")
                    } else {
                        ForEach(records.manifestations) { manifestation in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(manifestation.summary ?? manifestation.triggerReason)
                                HStack {
                                    Text(manifestation.status)
                                    Text("\(manifestation.proposalCount) proposals")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Automations") {
                    if records.cronJobs.isEmpty {
                        placeholder("No scheduled agent jobs.")
                    } else {
                        ForEach(records.cronJobs) { job in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(job.name)
                                    Text(job.state)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: job.enabled ? "checkmark.circle.fill" : "pause.circle")
                                    .foregroundStyle(job.enabled ? .green : .secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var mediaSections: some View {
        Group {
            Section("Gallery") {
                if let media {
                    LabeledContent("Root", value: media.root)
                    LabeledContent("Items", value: "\(media.items.count)")
                    HStack {
                        MediaCount(kind: .image, items: media.items)
                        MediaCount(kind: .video, items: media.items)
                        MediaCount(kind: .audio, items: media.items)
                    }
                } else {
                    placeholder("Media inventory has not loaded.")
                }
            }

            if let media {
                Section("Files") {
                    if media.items.isEmpty {
                        placeholder("No generated pictures, videos, or audio files in artifacts yet.")
                    } else {
                        ForEach(media.items) { item in
                            HStack(spacing: 12) {
                                Image(systemName: item.kind.systemImage)
                                    .frame(width: 24)
                                    .foregroundStyle(item.kind.tint)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.headline)
                                    Text(item.relativePath)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    Text(ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
        }
    }

    private func loadAll() async {
        guard session.isPaired, let client = session.client() else { return }
        isLoading = true
        errorText = nil
        statusMessage = nil
        defer { isLoading = false }

        do {
            providers = try await client.providers()
            selectedProviderID = providers?.preferredProviderID
                ?? providers?.activeProviderID
                ?? providers?.providers.first(where: \.isSelectableFromPhone)?.id
                ?? ""
            skills = try await client.skills()
            memories = try await client.memories()
            records = try await client.records()
            media = try await client.mediaGallery()
            await session.refresh()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func saveProviderKey(_ providerID: String) async {
        guard let client = session.client() else { return }
        let key = (keyDrafts[providerID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        isSavingProvider = true
        errorText = nil
        statusMessage = nil
        defer { isSavingProvider = false }

        do {
            let response = try await client.saveProviderKey(providerID: providerID, apiKey: key)
            providers = ProvidersResponse(
                providers: response.providers,
                activeProviderID: response.activeProviderID,
                preferredProviderID: response.preferredProviderID
            )
            selectedProviderID = response.preferredProviderID ?? selectedProviderID
            keyDrafts[providerID] = ""
            statusMessage = response.message
            await session.refresh()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func selectProvider() async {
        guard let client = session.client(), !selectedProviderID.isEmpty else { return }
        isSavingProvider = true
        errorText = nil
        statusMessage = nil
        defer { isSavingProvider = false }

        do {
            let response = try await client.selectProvider(providerID: selectedProviderID)
            providers = ProvidersResponse(
                providers: response.providers,
                activeProviderID: response.activeProviderID,
                preferredProviderID: response.preferredProviderID
            )
            statusMessage = response.message
            await session.refresh()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func keyBinding(for providerID: String) -> Binding<String> {
        Binding(
            get: { keyDrafts[providerID] ?? "" },
            set: { keyDrafts[providerID] = $0 }
        )
    }

    private func memoryItems(for status: MemoryStatus) -> [MemorySummary] {
        switch status {
        case .approved:
            return memories.approved
        case .pending:
            return memories.pending
        case .rejected:
            return memories.rejected
        }
    }

    private func providerName(id: String) -> String {
        providers?.providers.first { $0.id == id }?.name ?? id
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

private enum ControlSection: String, CaseIterable, Identifiable {
    case providers
    case knowledge
    case state
    case media

    var id: String { rawValue }

    var title: String {
        switch self {
        case .providers: "Models"
        case .knowledge: "Knowledge"
        case .state: "State"
        case .media: "Media"
        }
    }

    var systemImage: String {
        switch self {
        case .providers: "cpu"
        case .knowledge: "brain.head.profile"
        case .state: "list.bullet.rectangle"
        case .media: "photo.on.rectangle"
        }
    }
}

private enum MemoryStatus: String, CaseIterable, Identifiable {
    case approved
    case pending
    case rejected

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

private struct ProviderRow: View {
    let provider: ProviderSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(provider.name, systemImage: provider.iconName)
                    .font(.headline)
                Spacer()
                if provider.active {
                    Text("Active")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            HStack(spacing: 6) {
                ProviderChip(text: provider.locationLabel, systemImage: provider.locationIcon)
                ProviderChip(text: provider.costLabel, systemImage: provider.costIcon)
                ProviderChip(text: provider.configured ? "Ready" : provider.status, systemImage: provider.configured ? "checkmark.circle" : "exclamationmark.circle")
            }
            if let model = provider.model, !model.isEmpty {
                Text(model)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ProviderChip: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct MediaCount: View {
    let kind: MediaGalleryKind
    let items: [MediaGalleryItem]

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: kind.systemImage)
                .foregroundStyle(kind.tint)
            Text("\(items.filter { $0.kind == kind }.count)")
                .font(.headline)
            Text(kind.rawValue.capitalized)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private extension ProviderSummary {
    var acceptsPhoneKey: Bool {
        ["openai", "openrouter", "eliza-cloud"].contains(id)
    }

    var isSelectableFromPhone: Bool {
        id != "local-diagnostic"
    }

    var shortName: String {
        switch id {
        case "openai": "OpenAI"
        case "openrouter": "OpenRouter"
        case "eliza-cloud": "Eliza"
        default: name
        }
    }

    var iconName: String {
        switch id {
        case "local-openai", "local-diagnostic": "desktopcomputer"
        case "openrouter": "arrow.triangle.branch"
        case "eliza-cloud": "cloud"
        default: "sparkles"
        }
    }

    var locationLabel: String {
        id == "local-openai" || id == "local-diagnostic" ? "Local" : "Cloud"
    }

    var locationIcon: String {
        locationLabel == "Local" ? "macbook" : "cloud"
    }

    var costLabel: String {
        id == "local-openai" || id == "local-diagnostic" ? "Free" : "Paid"
    }

    var costIcon: String {
        costLabel == "Free" ? "checkmark.seal" : "creditcard"
    }
}

private extension SwooshReadinessStatus {
    var systemImage: String {
        switch self {
        case .ready: "checkmark.circle"
        case .warning: "exclamationmark.triangle"
        case .blocked: "xmark.octagon"
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
