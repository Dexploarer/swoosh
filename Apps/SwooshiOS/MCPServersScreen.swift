// Apps/SwooshiOS/MCPServersScreen.swift — Manage MCP server connections
//
// Lists every MCP server the user has configured, lets them add new ones
// from a template (filesystem, git, GitHub, etc.) or via a fully-custom
// form, and lets them tap into an existing entry for edit / delete.
//
// Persistence is local (UserDefaults under `ai.swoosh.mcp.servers.v1`)
// until the daemon-side `/api/mcp/servers` endpoint ships. The shape
// (`MCPServerEntry`) mirrors `SwooshMCP.MCPServerProfile` so the eventual
// sync is a one-to-one map. A footer on the list makes the local-only
// nature explicit so users don't expect the daemon to immediately pick
// up new entries.

import SwiftUI
import Observation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Model
// ═══════════════════════════════════════════════════════════════════

enum MCPTransportKind: String, Codable, CaseIterable, Identifiable {
    case stdio
    case http

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .stdio: return "Stdio (command)"
        case .http:  return "HTTP (URL)"
        }
    }
}

struct MCPServerEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var description: String
    var transport: MCPTransportKind
    // stdio fields
    var command: String
    var arguments: String          // space-separated for editing
    // http fields
    var url: String
    var enabled: Bool

    static let blank = MCPServerEntry(
        name: "",
        description: "",
        transport: .stdio,
        command: "",
        arguments: "",
        url: "",
        enabled: false
    )
}

// MARK: - Templates

struct MCPTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let blurb: String
    let symbol: String
    let entry: MCPServerEntry

    /// Common community MCP servers. Tapping one prefills the add sheet.
    static let all: [MCPTemplate] = [
        MCPTemplate(
            id: "filesystem",
            name: "Filesystem",
            blurb: "Read + write files in a sandboxed directory.",
            symbol: "folder",
            entry: MCPServerEntry(
                name: "Filesystem",
                description: "Filesystem MCP server, scoped to a single root.",
                transport: .stdio,
                command: "npx",
                arguments: "-y @modelcontextprotocol/server-filesystem ~/Documents",
                url: "",
                enabled: true
            )
        ),
        MCPTemplate(
            id: "git",
            name: "Git",
            blurb: "Inspect git repositories — log, blame, diff, status.",
            symbol: "arrow.triangle.branch",
            entry: MCPServerEntry(
                name: "Git",
                description: "Git MCP server (uvx).",
                transport: .stdio,
                command: "uvx",
                arguments: "mcp-server-git",
                url: "",
                enabled: true
            )
        ),
        MCPTemplate(
            id: "github",
            name: "GitHub",
            blurb: "Issues, PRs, search, repo metadata. Needs GITHUB_TOKEN.",
            symbol: "chevron.left.forwardslash.chevron.right",
            entry: MCPServerEntry(
                name: "GitHub",
                description: "Official GitHub MCP server.",
                transport: .stdio,
                command: "npx",
                arguments: "-y @modelcontextprotocol/server-github",
                url: "",
                enabled: true
            )
        ),
        MCPTemplate(
            id: "brave",
            name: "Brave Search",
            blurb: "Web search via the Brave API. Needs BRAVE_API_KEY.",
            symbol: "magnifyingglass",
            entry: MCPServerEntry(
                name: "Brave Search",
                description: "Web + news search.",
                transport: .stdio,
                command: "npx",
                arguments: "-y @modelcontextprotocol/server-brave-search",
                url: "",
                enabled: true
            )
        ),
        MCPTemplate(
            id: "postgres",
            name: "Postgres",
            blurb: "Read-only SQL access to a Postgres database.",
            symbol: "cylinder",
            entry: MCPServerEntry(
                name: "Postgres",
                description: "Read-only Postgres MCP server.",
                transport: .stdio,
                command: "npx",
                arguments: "-y @modelcontextprotocol/server-postgres postgresql://localhost/mydb",
                url: "",
                enabled: true
            )
        ),
        MCPTemplate(
            id: "memory",
            name: "Memory",
            blurb: "Knowledge-graph notes the agent can read and update.",
            symbol: "brain",
            entry: MCPServerEntry(
                name: "Memory",
                description: "Persistent agent memory store.",
                transport: .stdio,
                command: "npx",
                arguments: "-y @modelcontextprotocol/server-memory",
                url: "",
                enabled: true
            )
        ),
        MCPTemplate(
            id: "puppeteer",
            name: "Puppeteer",
            blurb: "Browser automation — screenshot, click, fill, navigate.",
            symbol: "globe",
            entry: MCPServerEntry(
                name: "Puppeteer",
                description: "Headless browser controlled by the agent.",
                transport: .stdio,
                command: "npx",
                arguments: "-y @modelcontextprotocol/server-puppeteer",
                url: "",
                enabled: true
            )
        ),
    ]
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Store
// ═══════════════════════════════════════════════════════════════════

@MainActor
@Observable
final class MCPServerStore {
    static let shared = MCPServerStore()
    private let key = "ai.swoosh.mcp.servers.v1"
    private(set) var servers: [MCPServerEntry] = []

    init() { reload() }

    func reload() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([MCPServerEntry].self, from: data) else {
            servers = []
            return
        }
        servers = list
    }

    func upsert(_ entry: MCPServerEntry) {
        if let idx = servers.firstIndex(where: { $0.id == entry.id }) {
            servers[idx] = entry
        } else {
            servers.append(entry)
        }
        persist()
    }

    func delete(_ entry: MCPServerEntry) {
        servers.removeAll { $0.id == entry.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - List screen
// ═══════════════════════════════════════════════════════════════════

struct MCPServersScreen: View {
    @State private var store = MCPServerStore.shared
    @State private var adding: MCPServerEntry?

    var body: some View {
        List {
            if store.servers.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No MCP servers yet", systemImage: "puzzlepiece.extension")
                    } description: {
                        Text("Pick a template below, or tap “Custom” to write your own.")
                    }
                }
            } else {
                Section("Connected") {
                    ForEach(store.servers) { server in
                        Button {
                            adding = server
                        } label: {
                            serverRow(server)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.delete(server)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section("Create") {
                Button {
                    adding = MCPServerEntry.blank
                } label: {
                    Label("Custom MCP server", systemImage: "plus.square.on.square")
                }
            }

            Section {
                ForEach(MCPTemplate.all) { template in
                    Button {
                        var entry = template.entry
                        entry.id = UUID()
                        adding = entry
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: template.symbol)
                                .frame(width: 28, alignment: .center)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name).font(.body.weight(.medium))
                                Text(template.blurb).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Templates")
            } footer: {
                Text("Tapping a template prefills the add form. You can edit every field before saving.")
            }
        }
        .navigationTitle("MCP Servers")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    adding = MCPServerEntry.blank
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add MCP server")
            }
        }
        .sheet(item: $adding) { entry in
            MCPServerEditSheet(initial: entry) { saved in
                store.upsert(saved)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text("Saved locally until the daemon-sync endpoint ships. Existing Mac-side MCP servers continue to load from the daemon as before.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(.thinMaterial)
        }
    }

    @ViewBuilder
    private func serverRow(_ server: MCPServerEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: server.transport == .stdio ? "terminal" : "network")
                .frame(width: 24)
                .foregroundStyle(server.enabled ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name.isEmpty ? "Untitled" : server.name)
                    .font(.body.weight(.medium))
                Text(serverSubtitle(server))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if !server.enabled {
                Text("Disabled")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: .capsule)
            }
        }
    }

    private func serverSubtitle(_ server: MCPServerEntry) -> String {
        switch server.transport {
        case .stdio:
            let argsTrimmed = server.arguments.trimmingCharacters(in: .whitespaces)
            return argsTrimmed.isEmpty ? server.command : "\(server.command) \(argsTrimmed)"
        case .http:
            return server.url
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Edit / Add sheet
// ═══════════════════════════════════════════════════════════════════

struct MCPServerEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entry: MCPServerEntry
    let onSave: (MCPServerEntry) -> Void

    init(initial: MCPServerEntry, onSave: @escaping (MCPServerEntry) -> Void) {
        self._entry = State(initialValue: initial)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Name", text: $entry.name)
                        .textInputAutocapitalization(.words)
                    TextField("Description (optional)", text: $entry.description, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Transport") {
                    Picker("Transport", selection: $entry.transport) {
                        ForEach(MCPTransportKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                switch entry.transport {
                case .stdio:
                    Section("Command") {
                        TextField("Command (e.g. npx, uvx, python)", text: $entry.command)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Arguments", text: $entry.arguments, axis: .vertical)
                            .lineLimit(1...4)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                case .http:
                    Section("Endpoint") {
                        TextField("Base URL", text: $entry.url)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }

                Section {
                    Toggle("Enabled", isOn: $entry.enabled)
                } footer: {
                    Text("Disabled servers stay in your list but the agent won't connect to them.")
                }
            }
            .navigationTitle(entry.name.isEmpty ? "New MCP server" : entry.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(entry)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private var isValid: Bool {
        guard !entry.name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch entry.transport {
        case .stdio: return !entry.command.trimmingCharacters(in: .whitespaces).isEmpty
        case .http:  return URL(string: entry.url) != nil && !entry.url.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}
