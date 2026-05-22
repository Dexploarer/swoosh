// Apps/SwooshiOS/ChannelsScreen.swift — Claude-style Channels surface (live)
//
// Sectioned list of every chat adapter swooshd knows about, fetched live
// from `GET /api/chat-adapters`. Each row shows the adapter's real
// configured / enabled status; tapping pushes a detail screen with
// capabilities, missing credentials, and an enable/disable toggle wired
// to `POST /api/chat-adapters/toggle`.
//
// The live wire format carries status but not category or human-readable
// descriptions, so the static `ChannelCatalog` mirror is joined in by id
// as a metadata sidecar. When the phone is unpaired (or the daemon fetch
// fails) the screen falls back to that static catalog, read-only.

import SwiftUI
import SwooshClient

struct ChannelsScreen: View {
    @Environment(ClientSession.self) private var session
    @State private var response: ChatAdaptersResponse?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var filter: ChannelFilter = .all
    /// True once the first paired load resolves — drives the full-bleed
    /// loading state instead of an inline "Loading…" row.
    @State private var hasLoadedOnce = false
    @State private var errorFeedback = 0

    enum ChannelFilter: String, CaseIterable, Identifiable {
        case all, official, vendor, community
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all:       "All"
            case .official:  "Official"
            case .vendor:    "Vendor"
            case .community: "Community"
            }
        }
        /// Distribution raw values (matching the wire format) this filter admits.
        func admits(_ distribution: String) -> Bool {
            switch self {
            case .all:       return true
            case .official:  return distribution == "official" || distribution == "internal"
            case .vendor:    return distribution == "vendorOfficial"
            case .community: return distribution == "community"
            }
        }
    }

    var body: some View {
        Group {
            // First paired load with no cached data — full-bleed states
            // so the screen never reads as blank or stale.
            if session.isPaired, response == nil, !hasLoadedOnce, isLoading {
                LoadingState("Loading channels…")
            } else if session.isPaired, response == nil, hasLoadedOnce, let errorText {
                ContentUnavailableView {
                    Label("Couldn't load channels", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                } description: {
                    Text(errorText)
                } actions: {
                    Button("Retry") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                listBody
            }
        }
        .navigationTitle("Channels")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: ChannelDestination.self) { destination in
            switch destination {
            case .platform(let id):
                if let summary = response?.adapters.first(where: { $0.id == id }) {
                    ChannelDetailScreen(
                        summary: summary,
                        meta: ChannelCatalog.entry(id: id),
                        onToggled: { self.response = $0 }
                    )
                } else {
                    ContentUnavailableView("Adapter not found", systemImage: "questionmark.circle")
                }
            case .state(let id):
                if let summary = response?.stateAdapters.first(where: { $0.id == id }) {
                    StateAdapterDetailScreen(
                        summary: summary,
                        onToggled: { self.response = $0 }
                    )
                } else {
                    ContentUnavailableView("State backend not found", systemImage: "questionmark.circle")
                }
            }
        }
        .task(id: session.host?.absoluteString) { await load() }
        .refreshable { await load() }
        .sensoryFeedback(.error, trigger: errorFeedback)
    }

    private var listBody: some View {
        List {
            Section {
                Picker("Filter", selection: $filter) {
                    ForEach(ChannelFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }

            content

            if let errorText {
                Section {
                    ErrorRow(message: errorText) { await load() }
                }
            }

            footer
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        if let response {
            liveSections(response)
        } else if isLoading {
            Section { LoadingRow("Loading channels…") }
        } else {
            fallbackSections
        }
    }

    // MARK: - Live (paired)

    /// Cached grouping for the current `response` + `filter` pair. Recomputed
    /// in `liveSections` via lazy `let`, but the heavy lifting only happens
    /// when one of those actually changes — not on every body re-render
    /// triggered by unrelated state. With 23 platform adapters + 7 state
    /// backends the un-cached version was triggering visible main-thread
    /// stalls when SwiftUI re-evaluated the list during navigation push.
    private struct GroupedAdapters {
        let platformByCategory: [(ChannelCategory, [ChannelRow])]
        let stateRows: [ChatStateAdapterSummary]
        var isEmpty: Bool {
            platformByCategory.allSatisfy { $0.1.isEmpty } && stateRows.isEmpty
        }
    }

    private func group(_ response: ChatAdaptersResponse, by filter: ChannelFilter) -> GroupedAdapters {
        let rows = response.adapters.compactMap { summary -> ChannelRow? in
            guard filter.admits(summary.distribution) else { return nil }
            return ChannelRow(summary: summary, meta: ChannelCatalog.entry(id: summary.id))
        }
        let platformByCategory: [(ChannelCategory, [ChannelRow])] = ChannelCategory.allCases.compactMap { category in
            let bucket = rows.filter { $0.category == category }
            return bucket.isEmpty ? nil : (category, bucket)
        }
        let stateRows = response.stateAdapters.filter { filter.admits($0.distribution) }
        return GroupedAdapters(platformByCategory: platformByCategory, stateRows: stateRows)
    }

    @ViewBuilder
    private func liveSections(_ response: ChatAdaptersResponse) -> some View {
        let grouped = group(response, by: filter)

        if grouped.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("No \(filter.title.lowercased()) channels", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text(filter == .all
                         ? "swooshd reported no chat adapters."
                         : "No adapters match the \(filter.title) filter. Switch to All to see everything.")
                } actions: {
                    if filter != .all {
                        Button("Show all") {
                            withAnimation(.easeOut(duration: 0.22)) { filter = .all }
                        }
                    }
                }
            }
        }

        // Platform adapters use `NavigationLink(value:)` + the screen-level
        // `.navigationDestination(for:)` so the destination view isn't built
        // until the user actually taps a row. The old form built every
        // ChannelDetailScreen eagerly, which compounded with 30 SVG-backed
        // logo views to stall the main thread.
        ForEach(grouped.platformByCategory, id: \.0) { (category, bucket) in
            Section(category.title) {
                ForEach(bucket) { row in
                    NavigationLink(value: ChannelDestination.platform(id: row.id)) {
                        ChannelRowView(
                            kindRawValue: row.summary.id,
                            displayName: row.summary.displayName,
                            distribution: row.summary.distribution,
                            enabled: row.summary.enabled,
                            configured: row.summary.configured,
                            missingCount: row.summary.missingCredentials.count
                        )
                    }
                }
            }
        }

        if !grouped.stateRows.isEmpty {
            Section {
                ForEach(grouped.stateRows) { adapter in
                    NavigationLink(value: ChannelDestination.state(id: adapter.id)) {
                        ChannelRowView(
                            kindRawValue: adapter.id,
                            displayName: adapter.displayName,
                            distribution: adapter.distribution,
                            enabled: adapter.enabled,
                            configured: adapter.configured,
                            missingCount: adapter.missingCredentials.count,
                            systemFallbackIcon: "cylinder.split.1x2.fill"
                        )
                    }
                }
            } header: {
                Text("State backends")
            } footer: {
                Text("State backends store conversation history and session state for the chat adapters above.")
            }
        }
    }

    // MARK: - Fallback (unpaired / offline)

    @ViewBuilder
    private var fallbackSections: some View {
        if !session.isPaired {
            Section {
                Label("Showing the offline catalog — pair this iPhone to see live status and toggle adapters.",
                      systemImage: "wifi.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        ForEach(ChannelCatalog.byCategory, id: \.0) { (category, entries) in
            let bucket = entries.filter { filter.admits(distributionRaw($0.distribution)) }
            if !bucket.isEmpty {
                Section(category.title) {
                    ForEach(bucket) { entry in
                        ChannelRowView(
                            kindRawValue: entry.kindRawValue,
                            displayName: entry.displayName,
                            distribution: distributionRaw(entry.distribution),
                            enabled: nil,
                            configured: nil,
                            missingCount: entry.credentialEnvVars.count
                        )
                    }
                }
            }
        }
    }

    /// Map the static `ChannelDistribution` onto the wire raw values.
    private func distributionRaw(_ distribution: ChannelDistribution) -> String {
        switch distribution {
        case .internalAdapter: "internal"
        case .official:        "official"
        case .vendorOfficial:  "vendorOfficial"
        case .community:       "community"
        }
    }

    private var footer: some View {
        Section {
            Text("Channels are enabled here and configured on swooshd by setting their env vars. Adapters pick up new toggles and credentials on the next daemon restart.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Load

    private func load() async {
        guard session.isPaired, let client = session.client() else {
            response = nil
            return
        }
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
        do {
            let loaded = try await client.chatAdapters()
            withAnimation(.easeOut(duration: 0.22)) { response = loaded }
        } catch {
            withAnimation(.easeOut(duration: 0.22)) { errorText = error.localizedDescription }
            errorFeedback &+= 1
        }
    }
}

// MARK: - Row model

/// A live platform adapter joined with its static catalog metadata.
private struct ChannelRow: Identifiable {
    let summary: ChatAdapterSummary
    let meta: ChannelCatalogEntry?
    var id: String { summary.id }
    var category: ChannelCategory { meta?.category ?? .internalSurface }
}

/// Destination value the NavigationStack pushes when the user taps a
/// chat-adapter row. We only carry the id+kind (both Hashable) so the
/// wire types (`ChatAdapterSummary` / `ChatStateAdapterSummary`) don't
/// need to adopt Hashable in the public SwooshClient surface. The
/// destination view looks the row up by id from the currently loaded
/// response. Using `NavigationLink(value:)` + screen-level
/// `.navigationDestination(for:)` keeps detail screens lazy — building
/// 30 inline `NavigationLink { destination } label:` views was the
/// freeze culprit when the list first rendered.
private enum ChannelDestination: Hashable {
    case platform(id: String)
    case state(id: String)
}

// MARK: - Row view

/// One adapter row. `enabled` / `configured` are nil in the offline
/// fallback, where status is unknown.
private struct ChannelRowView: View {
    let kindRawValue: String
    let displayName: String
    let distribution: String
    let enabled: Bool?
    let configured: Bool?
    let missingCount: Int
    var systemFallbackIcon: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            // State backends have no bundled brand mark — render a uniform
            // database glyph instead of a two-letter monogram. Platform
            // adapters fall through to ChannelLogo (brand SVG → monogram).
            if let systemFallbackIcon {
                IconTile(systemName: systemFallbackIcon, tint: .teal, size: 36, cornerRadius: 10)
            } else {
                ChannelLogo(kindRawValue: kindRawValue, displayName: displayName, size: 36)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.body.weight(.semibold))
                HStack(spacing: 6) {
                    DistributionPill(distribution: distribution)
                    statusPill
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusPill: some View {
        if let enabled, let configured {
            switch (enabled, configured) {
            case (true, true):
                StatusPill(text: "On", tint: .green)
            case (true, false):
                StatusPill(text: "On · unconfigured", tint: .orange)
            case (false, true):
                StatusPill(text: "Off", tint: .secondary)
            case (false, false):
                StatusPill(text: missingCount > 0 ? "\(missingCount) key\(missingCount == 1 ? "" : "s") needed" : "Setup needed",
                           tint: .orange)
            }
        } else if missingCount > 0 {
            StatusPill(text: "\(missingCount) env var\(missingCount == 1 ? "" : "s")", tint: .orange)
        } else {
            StatusPill(text: "Catalogued", tint: .secondary)
        }
    }
}

private struct DistributionPill: View {
    let distribution: String
    var body: some View {
        StatusPill(text: ChannelDistributionStyle.label(distribution),
                   tint: ChannelDistributionStyle.tint(distribution))
    }
}

private struct StatusPill: View {
    let text: String
    let tint: Color
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.18)))
            .foregroundStyle(tint)
    }
}

enum ChannelDistributionStyle {
    static func label(_ raw: String) -> String {
        switch raw {
        case "internal":       "Internal"
        case "official":       "Official"
        case "vendorOfficial": "Vendor"
        case "community":      "Community"
        default:               raw.capitalized
        }
    }
    static func tint(_ raw: String) -> Color {
        switch raw {
        case "internal":       .secondary
        case "official":       .blue
        case "vendorOfficial": .purple
        case "community":      .teal
        default:               .gray
        }
    }
}

// MARK: - Platform adapter detail

struct ChannelDetailScreen: View {
    @Environment(ClientSession.self) private var session
    let summary: ChatAdapterSummary
    let meta: ChannelCatalogEntry?
    let onToggled: (ChatAdaptersResponse) -> Void

    @State private var enabled: Bool
    @State private var toggling = false
    @State private var error: String?
    @State private var toggleFeedback = 0
    @State private var errorFeedback = 0

    init(summary: ChatAdapterSummary, meta: ChannelCatalogEntry?, onToggled: @escaping (ChatAdaptersResponse) -> Void) {
        self.summary = summary
        self.meta = meta
        self.onToggled = onToggled
        _enabled = State(initialValue: summary.enabled)
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ChannelLogo(kindRawValue: summary.id, displayName: summary.displayName, size: 56, cornerRadius: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.displayName).font(.title3.weight(.semibold))
                        Text(ChannelDistributionStyle.label(summary.distribution))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Toggle(isOn: Binding(get: { enabled }, set: { newValue in Task { await setEnabled(newValue) } })) {
                    HStack {
                        Text("Enabled")
                        if toggling { ProgressView().controlSize(.small) }
                    }
                }
            } footer: {
                Text(enabled
                     ? "swooshd will start this adapter on the next daemon restart."
                     : "Disabled adapters are skipped when swooshd starts.")
            }

            Section("Status") {
                LabeledContent("Configured", value: summary.configured ? "Yes" : "Needs setup")
                LabeledContent("Running state", value: enabled ? "Enabled" : "Disabled")
            }

            if let description = meta?.description {
                Section("About") {
                    Text(description).font(.body)
                }
            }

            capabilitiesSection

            if !summary.missingCredentials.isEmpty {
                Section {
                    ForEach(summary.missingCredentials, id: \.self) { envVar in
                        HStack(spacing: 10) {
                            IconTile(systemName: "key.fill", tint: .orange, size: 28)
                            Text(envVar)
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                } header: {
                    Text("Missing credentials")
                } footer: {
                    Text("Set these in swooshd's environment (or `~/.swoosh/config.json`) and restart the daemon.")
                }
            }

            if !summary.configurationNotes.isEmpty {
                Section("Configuration notes") {
                    ForEach(summary.configurationNotes, id: \.self) { note in
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }

            if let pkg = summary.packageName {
                Section("Package") {
                    HStack(spacing: 10) {
                        IconTile(systemName: "shippingbox.fill", tint: .indigo, size: 28)
                        Text(pkg)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }

            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red).font(.footnote)
                } footer: {
                    Text("The toggle was reverted — try again when the daemon is reachable.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(summary.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: toggleFeedback)
        .sensoryFeedback(.error, trigger: errorFeedback)
    }

    @ViewBuilder
    private var capabilitiesSection: some View {
        let caps: [(String, Bool)] = [
            ("Streaming", summary.supportsStreaming),
            ("Direct messages", summary.supportsDMs),
            ("Cards", summary.supportsCards),
            ("Modals", summary.supportsModals),
        ]
        if caps.contains(where: \.1) {
            Section("Capabilities") {
                ForEach(caps.filter(\.1), id: \.0) { cap in
                    Label(cap.0, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.primary)
                        .labelStyle(.titleAndIcon)
                }
            }
        }
    }

    private func setEnabled(_ newValue: Bool) async {
        guard let client = session.client(), !toggling else { return }
        toggling = true
        error = nil
        withAnimation(.easeOut(duration: 0.22)) { enabled = newValue }
        toggleFeedback &+= 1   // haptic: toggle flipped
        defer { toggling = false }
        do {
            let updated = try await client.setChatAdapter(id: summary.id, enabled: newValue)
            onToggled(updated)
        } catch {
            withAnimation(.easeOut(duration: 0.22)) {
                enabled = !newValue   // revert optimistic flip
                self.error = error.localizedDescription
            }
            errorFeedback &+= 1   // haptic: toggle failed
        }
    }
}

// MARK: - State adapter detail

struct StateAdapterDetailScreen: View {
    @Environment(ClientSession.self) private var session
    let summary: ChatStateAdapterSummary
    let onToggled: (ChatAdaptersResponse) -> Void

    @State private var enabled: Bool
    @State private var toggling = false
    @State private var error: String?
    @State private var toggleFeedback = 0
    @State private var errorFeedback = 0

    init(summary: ChatStateAdapterSummary, onToggled: @escaping (ChatAdaptersResponse) -> Void) {
        self.summary = summary
        self.onToggled = onToggled
        _enabled = State(initialValue: summary.enabled)
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    IconTile(systemName: "cylinder.split.1x2.fill", tint: .teal, size: 56, cornerRadius: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.displayName).font(.title3.weight(.semibold))
                        Text(ChannelDistributionStyle.label(summary.distribution))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Toggle(isOn: Binding(get: { enabled }, set: { newValue in Task { await setEnabled(newValue) } })) {
                    HStack {
                        Text("Enabled")
                        if toggling { ProgressView().controlSize(.small) }
                    }
                }
            } footer: {
                Text("Only one state backend is used at a time; swooshd resolves the active one on restart.")
            }

            Section("Status") {
                LabeledContent("Configured", value: summary.configured ? "Yes" : "Needs setup")
                LabeledContent("Production-ready", value: summary.productionReady ? "Yes" : "Dev / test only")
                LabeledContent("Running state", value: enabled ? "Enabled" : "Disabled")
            }

            if !summary.missingCredentials.isEmpty {
                Section {
                    ForEach(summary.missingCredentials, id: \.self) { envVar in
                        HStack(spacing: 10) {
                            IconTile(systemName: "key.fill", tint: .orange, size: 28)
                            Text(envVar)
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                } header: {
                    Text("Missing credentials")
                } footer: {
                    Text("Set these in swooshd's environment and restart the daemon.")
                }
            }

            if !summary.configurationNotes.isEmpty {
                Section("Configuration notes") {
                    ForEach(summary.configurationNotes, id: \.self) { note in
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }

            if let pkg = summary.packageName {
                Section("Package") {
                    HStack(spacing: 10) {
                        IconTile(systemName: "shippingbox.fill", tint: .indigo, size: 28)
                        Text(pkg)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }

            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red).font(.footnote)
                } footer: {
                    Text("The toggle was reverted — try again when the daemon is reachable.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(summary.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: toggleFeedback)
        .sensoryFeedback(.error, trigger: errorFeedback)
    }

    private func setEnabled(_ newValue: Bool) async {
        guard let client = session.client(), !toggling else { return }
        toggling = true
        error = nil
        withAnimation(.easeOut(duration: 0.22)) { enabled = newValue }
        toggleFeedback &+= 1
        defer { toggling = false }
        do {
            let updated = try await client.setChatAdapter(id: summary.id, enabled: newValue)
            onToggled(updated)
        } catch {
            withAnimation(.easeOut(duration: 0.22)) {
                enabled = !newValue
                self.error = error.localizedDescription
            }
            errorFeedback &+= 1
        }
    }
}
