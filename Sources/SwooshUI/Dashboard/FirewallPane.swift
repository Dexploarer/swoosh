// SwooshUI/Dashboard/FirewallPane.swift — Firewall permission grants — 0.9Y
//
// Lists GET /api/firewall/grants (granted + denied) and revokes a grant via
// DELETE /api/firewall/grants/:permission. The actual enforcement stays at
// SwooshFirewallActor.require on the daemon — this only shows names and sends
// revoke decisions. Reserved-admin permissions cannot be granted from here.

#if os(macOS)
import SwiftUI
import SwooshGenerativeUI
import SwooshClient

public struct FirewallPane: View {
    @State private var firewall: FirewallResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var busy: Set<String> = []

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(SwooshNeonTokens.Line.rule)
            if isLoading && firewall == nil {
                loading
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(VoltPaper.destructive)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        grantedSection
                        deniedSection
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
                Text("Firewall")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                Text("\(firewall?.granted.count ?? 0) granted · \(firewall?.denied.count ?? 0) denied")
                    .font(.system(size: 12))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            }
            Spacer()
            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            }
            Button { Task { await load() } } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text2)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
    }

    @ViewBuilder
    private var grantedSection: some View {
        let granted = firewall?.granted.sorted() ?? []
        Text("GRANTED")
            .font(.system(size: 9, weight: .semibold)).tracking(1.5)
            .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            .padding(.leading, 4).padding(.bottom, 2)
        if granted.isEmpty {
            Text("No permissions granted.")
                .font(.system(size: 12))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                .padding(.bottom, 8)
        } else {
            ForEach(granted, id: \.self) { permission in
                permissionRow(permission, granted: true)
            }
        }
    }

    @ViewBuilder
    private var deniedSection: some View {
        let denied = firewall?.denied.sorted() ?? []
        if !denied.isEmpty {
            Text("DENIED")
                .font(.system(size: 9, weight: .semibold)).tracking(1.5)
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                .padding(.top, 16).padding(.leading, 4).padding(.bottom, 2)
            ForEach(denied, id: \.self) { permission in
                permissionRow(permission, granted: false)
            }
        }
    }

    private func permissionRow(_ permission: String, granted: Bool) -> some View {
        let isBusy = busy.contains(permission)
        return HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(granted ? VoltPaper.accent : SwooshNeonTokens.Canvas.text3)
            Text(permission)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(SwooshNeonTokens.Canvas.text1)
            Spacer()
            if granted {
                Button { Task { await revoke(permission) } } label: {
                    Text("Revoke")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(VoltPaper.destructive)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(Capsule().fill(VoltPaper.destructive.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(VoltPaper.foreground.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(SwooshNeonTokens.Line.rule, lineWidth: 0.5)
        )
        .opacity(isBusy ? 0.6 : 1)
    }

    private var loading: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Loading firewall…")
                .font(.system(size: 12))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            firewall = try await client.firewallGrants()
            errorMessage = nil
        } catch {
            errorMessage = "Failed: \(error.localizedDescription)"
        }
    }

    private func revoke(_ permission: String) async {
        guard let client = SwooshDaemonClient.client() else { return }
        busy.insert(permission)
        defer { busy.remove(permission) }
        do {
            firewall = try await client.revokeFirewall(permission: permission)
            statusMessage = "Revoked \(permission)."
        } catch {
            statusMessage = "Revoke failed: \(error.localizedDescription)"
        }
    }
}

#endif
