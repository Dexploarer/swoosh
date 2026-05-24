// SwooshUI/DashboardPanes/ApprovalsPane.swift — Approval queue dashboard pane — 0.9U

#if os(macOS)

import SwiftUI
import SwooshClient
import SwooshConfig
import SwooshCore
import SwooshGenerativeUI
import SwooshModels
import SwooshTools

struct ApprovalsPane: View {
    let snapshot: DashboardRuntimeSnapshot
    @Environment(\.swooshTheme) var theme
    @State private var pendingRows: [ApprovalSummary] = []
    @State private var historyRows: [ApprovalSummary] = []
    @State private var isLoading = false
    @State private var error: String?

    init(snapshot: DashboardRuntimeSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        DashboardPane(
            title: "Approvals",
            icon: "hand.raised.fill",
            subtitle: "Pending tool calls awaiting human approval"
        ) {
            if let error {
                OfflineBanner(reason: error)
            }
            if !snapshot.daemonReachable {
                OfflineBanner(reason: "Daemon offline — approval queue is unreachable.")
            }

            HStack(spacing: 10) {
                StatBadge(value: "\(pendingRows.count)", label: "Pending", tint: .yellow)
                StatBadge(value: "\(historyRows.count)", label: "History", tint: .blue)
                StatBadge(
                    value: snapshot.readiness.component(id: "approvals")?.detail ?? "Gated",
                    label: "Policy",
                    tint: .green
                )
            }

            PaneCard {
                sectionHeader("PENDING")
                if pendingRows.isEmpty {
                    emptyState(icon: "checkmark.seal", text: "No approvals waiting.")
                } else {
                    ForEach(pendingRows) { row in
                        approvalRow(row)
                    }
                }
            }

            PaneCard {
                sectionHeader("RECENT DECISIONS")
                if historyRows.isEmpty {
                    emptyState(icon: "clock", text: "No decisions yet.")
                } else {
                    ForEach(historyRows) { row in
                        ListRow(
                            icon: row.status == "denied" ? "xmark.circle.fill" : "checkmark.circle.fill",
                            iconTint: row.status == "denied" ? .red : .green,
                            title: row.toolName,
                            subtitle: row.inputPreview,
                            trailing: row.status.capitalized
                        )
                    }
                }
            }
        }
        .task { await load() }
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

    private func approvalRow(_ row: ApprovalSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.yellow)
                .frame(width: 22, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.toolName).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(theme.textPrimary)
                Text(row.inputPreview).font(.system(size: 11, weight: .medium)).foregroundStyle(theme.textPrimary.opacity(0.6))
            }
            Spacer(minLength: 8)
            Button("Approve") {
                Task { await resolve(row, decision: .approveOnce) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.green)
            Button("Deny") {
                Task { await resolve(row, decision: .deny) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func emptyState(icon: String, text: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 22)).foregroundStyle(theme.textPrimary.opacity(0.35))
                Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(theme.textPrimary.opacity(0.55))
            }
            Spacer()
        }
        .padding(20)
    }

    private func load() async {
        guard let client = makeClient() else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await client.approvals()
            pendingRows = response.pending
            historyRows = response.history
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func resolve(_ row: ApprovalSummary, decision: ApprovalResolveRequest.Decision) async {
        guard let client = makeClient() else { return }
        do {
            _ = try await client.resolveApproval(
                id: row.id,
                request: ApprovalResolveRequest(decision: decision)
            )
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Tools
// ═══════════════════════════════════════════════════════════════════

#endif
