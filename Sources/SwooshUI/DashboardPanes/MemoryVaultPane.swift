// SwooshUI/DashboardPanes/MemoryVaultPane.swift — Memory review dashboard pane — 0.9U

#if os(macOS)

import SwiftUI
import SwooshClient
import SwooshConfig
import SwooshCore
import SwooshGenerativeUI
import SwooshModels
import SwooshTools

struct MemoryVaultPane: View {
    let snapshot: DashboardRuntimeSnapshot
    @Environment(\.swooshTheme) var theme
    @State private var memories: MemoriesResponse?
    @State private var isLoading = false
    @State private var error: String?

    init(snapshot: DashboardRuntimeSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        DashboardPane(
            title: "Memory Vault",
            icon: "brain.head.profile",
            subtitle: "Approved, pending, and rejected memories"
        ) {
            if !snapshot.daemonReachable {
                OfflineBanner(reason: "Daemon offline — showing local files only.")
            }

            HStack(spacing: 10) {
                StatBadge(value: "\(memories?.approved.count ?? 0)", label: "Approved", tint: .green)
                StatBadge(value: "\(memories?.pending.count ?? 0)", label: "Pending", tint: .orange)
                StatBadge(value: "\(memories?.rejected.count ?? 0)", label: "Rejected", tint: .red)
                StatBadge(value: "\(snapshot.local.memoryFiles)", label: "Files", tint: .cyan)
            }

            if let pending = memories?.pending, !pending.isEmpty {
                PaneCard {
                    sectionHeader("PENDING — REVIEW")
                    ForEach(pending) { mem in
                        memoryRow(mem)
                    }
                }
            }

            PaneCard {
                sectionHeader("APPROVED")
                if let approved = memories?.approved, !approved.isEmpty {
                    ForEach(approved) { mem in
                        memoryRow(mem)
                    }
                } else {
                    emptyState(icon: "brain", text: isLoading ? "Loading…" : "No approved memories yet.")
                }
            }

            if let rejected = memories?.rejected, !rejected.isEmpty {
                PaneCard {
                    sectionHeader("REJECTED")
                    ForEach(rejected) { mem in
                        memoryRow(mem)
                    }
                }
            }
        }
        .task { await load() }
    }

    private func memoryRow(_ mem: MemorySummary) -> some View {
        ListRow(
            icon: "brain",
            iconTint: sensitivityColor(mem.sensitivity),
            title: mem.text,
            subtitle: "\(mem.category) · \(mem.sensitivity)" + (mem.confidence.map { " · \(Int($0 * 100))%" } ?? ""),
            trailing: mem.status.capitalized,
            trailingTint: statusColor(mem.status)
        )
    }

    private func sensitivityColor(_ s: String) -> Color {
        switch s.lowercased() {
        case "high":   return .red
        case "medium": return .orange
        case "low":    return .green
        default:       return .secondary
        }
    }

    private func statusColor(_ s: String) -> Color {
        switch s.lowercased() {
        case "approved": return .green
        case "pending":  return .orange
        case "rejected": return .red
        default:         return .secondary
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold))
            .tracking(1.4)
            .foregroundStyle(theme.textPrimary.opacity(0.55))
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }

    private func emptyState(icon: String, text: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(theme.textPrimary.opacity(0.35))
                Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(theme.textPrimary.opacity(0.55))
            }
            Spacer()
        }
        .padding(16)
    }

    private func load() async {
        guard let client = makeClient() else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            memories = try await client.memories()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Local Models
// ═══════════════════════════════════════════════════════════════════

#endif
