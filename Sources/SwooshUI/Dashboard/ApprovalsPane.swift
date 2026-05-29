// SwooshUI/Dashboard/ApprovalsPane.swift — Human-in-the-loop approval queue — 0.9Y
//
// Lists GET /api/approvals (pending + history) and resolves each via
// POST /api/approvals/:id/resolve. This is the human gate: askEveryTime /
// askFirstTime tool calls (and critical actions like a token launch) wait
// here for an explicit approve/deny. The model can never resolve these.

#if os(macOS)
import SwiftUI
import SwooshGenerativeUI
import SwooshClient

public struct ApprovalsPane: View {
    @State private var pending: [ApprovalSummary] = []
    @State private var history: [ApprovalSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var busy: Set<String> = []

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(SwooshNeonTokens.Line.rule)
            if isLoading && pending.isEmpty {
                loading
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(VoltPaper.destructive)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if pending.isEmpty {
                            emptyState
                        } else {
                            ForEach(pending) { approvalRow($0, resolvable: true) }
                        }
                        if !history.isEmpty {
                            Text("HISTORY")
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(1.5)
                                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                                .padding(.top, 16).padding(.leading, 4)
                            ForEach(history.prefix(40)) { approvalRow($0, resolvable: false) }
                        }
                    }
                    .padding(24)
                }
            }
        }
        .background(SwooshNeonTokens.Canvas.bg)
        .task { await load() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Approvals")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                Text("\(pending.count) pending")
                    .font(.system(size: 12))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            }
            Spacer()
            Button { Task { await load() } } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text2)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
    }

    private func approvalRow(_ approval: ApprovalSummary, resolvable: Bool) -> some View {
        let isBusy = busy.contains(approval.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(approval.toolName)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                riskBadge(approval.risk)
                Spacer()
                if !resolvable {
                    Text(approval.status.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(statusColor(approval.status))
                }
            }
            Text(approval.inputPreview)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                .lineLimit(3)
            HStack(spacing: 8) {
                Text(approval.permission)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(VoltPaper.Chart.c1)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(VoltPaper.Chart.c1.opacity(0.12))
                    .clipShape(Capsule())
                Spacer()
                if resolvable {
                    resolveButtons(approval, isBusy: isBusy)
                }
            }
        }
        .padding(12)
        .background(VoltPaper.foreground.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(resolvable ? VoltPaper.Chart.c4.opacity(0.3) : SwooshNeonTokens.Line.rule, lineWidth: 0.5)
        )
        .opacity(isBusy ? 0.6 : 1)
    }

    private func resolveButtons(_ approval: ApprovalSummary, isBusy: Bool) -> some View {
        HStack(spacing: 6) {
            pill("Deny", color: VoltPaper.destructive, fill: false) {
                Task { await resolve(approval, .deny) }
            }
            pill("Once", color: VoltPaper.accent, fill: false) {
                Task { await resolve(approval, .approveOnce) }
            }
            pill("Session", color: VoltPaper.accent, fill: true) {
                Task { await resolve(approval, .approveForSession) }
            }
        }
        .disabled(isBusy)
    }

    private func pill(_ label: String, color: Color, fill: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(fill ? VoltPaper.accentFg : color)
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(Capsule().fill(fill ? color : color.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private func riskBadge(_ risk: String) -> some View {
        let color: Color = risk == "critical" ? VoltPaper.destructive :
                           risk == "high" ? VoltPaper.Chart.c4 :
                           risk == "medium" ? VoltPaper.Chart.c1 : VoltPaper.mutedFg
        return Text(risk.uppercased())
            .font(.system(size: 8, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "approved", "approvedonce", "approvedforsession": return VoltPaper.accent
        case "denied": return VoltPaper.destructive
        default: return VoltPaper.mutedFg
        }
    }

    private var loading: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Loading approvals…")
                .font(.system(size: 12))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3.opacity(0.4))
            Text("Nothing waiting for approval")
                .font(.system(size: 14))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Network

    private func load() async {
        guard let client = SwooshDaemonClient.client() else {
            errorMessage = "Daemon not reachable."
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await client.approvals()
            pending = response.pending
            history = response.history
            errorMessage = nil
        } catch {
            errorMessage = "Failed: \(error.localizedDescription)"
        }
    }

    private func resolve(_ approval: ApprovalSummary, _ decision: ApprovalResolveRequest.Decision) async {
        guard let client = SwooshDaemonClient.client() else { return }
        busy.insert(approval.id)
        defer { busy.remove(approval.id) }
        do {
            _ = try await client.resolveApproval(id: approval.id, request: ApprovalResolveRequest(decision: decision))
            await load()
        } catch {
            errorMessage = "Resolve failed: \(error.localizedDescription)"
        }
    }
}

#endif
