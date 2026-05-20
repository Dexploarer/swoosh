// Apps/SwooshiOS/ChannelsScreen.swift — Claude-style Channels surface
//
// Sectioned list of every chat adapter swooshd knows about. Each row
// uses ChannelLogo + the distribution pill (Official / Vendor /
// Community / Internal). Tap pushes ChannelDetailScreen with the
// description and the required-credentials env-var list.
//
// Channel status (configured vs not) waits on a `/api/agent/channels`
// daemon endpoint — until then every row shows a neutral "Not
// configured" pill except internal adapters, which are always ready.

import SwiftUI

struct ChannelsScreen: View {
    @State private var filter: ChannelFilter = .all

    enum ChannelFilter: String, CaseIterable, Identifiable {
        case all, official, community, internalAdapter
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all:             "All"
            case .official:        "Official"
            case .community:       "Community"
            case .internalAdapter: "Internal"
            }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Filter", selection: $filter) {
                    ForEach(ChannelFilter.allCases) { f in
                        Text(f.title).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }

            ForEach(filteredCategories, id: \.0) { (category, entries) in
                Section(category.title) {
                    ForEach(entries) { entry in
                        NavigationLink(value: entry) {
                            ChannelRow(entry: entry)
                        }
                    }
                }
            }

            Section {
                Text("Channels are configured on swooshd by setting their env vars and restarting the daemon. A live status feed is coming once `/api/agent/channels` ships.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Channels")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: ChannelCatalogEntry.self) { entry in
            ChannelDetailScreen(entry: entry)
        }
    }

    private var filteredCategories: [(ChannelCategory, [ChannelCatalogEntry])] {
        ChannelCatalog.byCategory.compactMap { (category, entries) in
            let filtered = entries.filter { entry in
                switch filter {
                case .all:             return true
                case .official:        return entry.distribution == .official
                case .community:       return entry.distribution == .community
                case .internalAdapter: return entry.distribution == .internalAdapter || entry.distribution == .vendorOfficial
                }
            }
            return filtered.isEmpty ? nil : (category, filtered)
        }
    }
}

private struct ChannelRow: View {
    let entry: ChannelCatalogEntry

    var body: some View {
        HStack(spacing: 12) {
            ChannelLogo(
                kindRawValue: entry.kindRawValue,
                displayName: entry.displayName,
                size: 36
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayName)
                    .font(.body.weight(.semibold))
                HStack(spacing: 6) {
                    distributionPill
                    statusPill
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var distributionPill: some View {
        Text(entry.distribution.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(distributionTint.opacity(0.18)))
            .foregroundStyle(distributionTint)
    }

    @ViewBuilder
    private var statusPill: some View {
        if entry.distribution == .internalAdapter {
            Text("Always on")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.green.opacity(0.18)))
                .foregroundStyle(.green)
        } else if entry.credentialEnvVars.isEmpty {
            Text("Vendor-configured")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.gray.opacity(0.18)))
                .foregroundStyle(.gray)
        } else {
            Text("\(entry.credentialEnvVars.count) env var\(entry.credentialEnvVars.count == 1 ? "" : "s")")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.orange.opacity(0.18)))
                .foregroundStyle(.orange)
        }
    }

    private var distributionTint: Color {
        switch entry.distribution {
        case .official:        return .blue
        case .vendorOfficial:  return .purple
        case .community:       return .teal
        case .internalAdapter: return .secondary
        }
    }
}

// MARK: - Detail

struct ChannelDetailScreen: View {
    let entry: ChannelCatalogEntry

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ChannelLogo(
                        kindRawValue: entry.kindRawValue,
                        displayName: entry.displayName,
                        size: 56,
                        cornerRadius: 14
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.displayName)
                            .font(.title3.weight(.semibold))
                        Text(entry.distribution.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("About") {
                Text(entry.description)
                    .font(.body)
            }

            if let pkg = entry.packageName {
                Section("Package") {
                    HStack(spacing: 10) {
                        IconTile(systemName: "shippingbox.fill", tint: .indigo, size: 28)
                        Text(pkg)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }

            if !entry.credentialEnvVars.isEmpty {
                Section {
                    ForEach(entry.credentialEnvVars, id: \.self) { envVar in
                        HStack(spacing: 10) {
                            IconTile(systemName: "key.fill", tint: .orange, size: 28)
                            Text(envVar)
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                } header: {
                    Text("Required env vars")
                } footer: {
                    Text("Set these in swooshd's environment (or `~/.swoosh/config.json`) and restart the daemon to bring this channel online.")
                }
            } else if entry.distribution == .vendorOfficial || entry.distribution == .community {
                Section {
                    Text("Configuration is managed by the vendor / community package. See the package README for setup steps.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(entry.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
