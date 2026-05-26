// DetourHomeDashboard.swift — command-first Detour workspace (0.5A)

import SwiftUI

struct DetourHomeDashboard: View {
    @ObservedObject var store: OnboardingStore
    let sections: [DetourSetupInsightSection]
    let summary: DetourSetupCapabilitySummary
    @Binding var focus: DetourHomeFocus
    @Binding var command: String
    @ObservedObject var wallet: DetourHomeWalletModel
    @ObservedObject var inbox: DetourHomeInboxModel
    let runningScan: Bool
    let applyingSetup: Bool
    let chatIntegrationSurface: DetourChatIntegrationSurface?
    let submitCommand: () -> Void
    let reviewSetup: () -> Void
    let applySetup: () -> Void
    let runScan: () -> Void
    let openCanvas: () -> Void
    let action: (DetourSetupInsightAction) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                sideRail
                ScrollView {
                    VStack(spacing: 18) {
                        identityBlock
                            .padding(.top, focus == .overview ? 58 : 28)
                        if focus == .overview {
                            if let chatIntegrationSurface {
                                DetourChatIntegrationSurfaceView(
                                    surface: chatIntegrationSurface,
                                    store: store
                                )
                            }
                            Spacer(minLength: chatIntegrationSurface == nil ? 300 : 120)
                        } else {
                            focusedSurface
                                .frame(maxWidth: 980)
                            Spacer(minLength: 140)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 36)
                }
            }
            if focus == .overview {
                commandComposer
                    .padding(.leading, 74)
                    .padding(.trailing, 36)
                    .padding(.bottom, 28)
            }
        }
    }

    private var sideRail: some View {
        VStack(spacing: 14) {
            railButton(.overview)
            Divider().overlay(.white.opacity(0.16))
            railButton(.apps)
            railButton(.social)
            railButton(.inbox)
            railButton(.wallet)
            railButton(.setup)
            railButton(.settings)
            Spacer()
            Button(action: openCanvas) {
                Image(systemName: "square.grid.3x3")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .help("Open canvas")
        }
        .padding(.vertical, 18)
        .frame(width: 62)
        .background(.ultraThinMaterial.opacity(0.52))
        .overlay(alignment: .trailing) {
            Rectangle().fill(.white.opacity(0.12)).frame(width: 1)
        }
    }

    private func railButton(_ item: DetourHomeFocus) -> some View {
        Button {
            focus = item
        } label: {
            Image(systemName: item.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(focus == item ? .white : .white.opacity(0.62))
                .frame(width: 34, height: 34)
                .background(focus == item ? .white.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help(item.title)
        .accessibilityLabel(item.title)
    }

    private var identityBlock: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white)
                    .frame(width: 62, height: 62)
                    .shadow(color: Color(red: 0.98, green: 0.65, blue: 0.25).opacity(0.12), radius: 16)
                Image(systemName: "sparkles")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(.orange)
            }
            Text(agentName)
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)
        }
        .multilineTextAlignment(.center)
    }

    private var focusedSurface: some View {
        Group {
            switch focus {
            case .overview:
                EmptyView()
            case .apps:
                appsSurface
            case .social:
                socialSurface
            case .inbox:
                DetourHomeInboxPanel(inbox: inbox, reviewSetup: reviewSetup)
            case .wallet:
                walletSurface
            case .setup:
                setupSurface
            case .settings:
                DetourHomeSettingsPanel(
                    store: store,
                    scan: runScan,
                    applySetup: applySetup,
                    reviewSetup: reviewSetup
                )
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }

    private var appsSurface: some View {
        DetourIntegrationCatalogView(
            store: store,
            scan: runScan,
            test: applySetup
        )
        .padding(22)
        .detourLiquidGlass(cornerRadius: 26)
    }

    private var socialSurface: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Social")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                ForEach(socialItems.prefix(8)) { item in
                    DetourHomeItemRow(item: item, action: action)
                }
            }
            HStack {
                Button("Test", action: applySetup)
                    .buttonStyle(.borderedProminent)
                Button("Setup", action: reviewSetup)
                    .buttonStyle(.bordered)
            }
        }
        .padding(22)
        .detourLiquidGlass(cornerRadius: 26)
    }

    private var walletSurface: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Wallets")
            if let dashboard = wallet.dashboard {
                HStack(spacing: 12) {
                    metric("Wallet", dashboard.connected ? "Connected" : "Setup", dashboard.walletLabel ?? "")
                    metric("Assets", "\(dashboard.assets.count)", "")
                    metric("Alerts", "\(dashboard.insights.count)", "")
                }
            } else {
                Text(wallet.state.label)
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("Solana, BNB, EVM, Hyperliquid.")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Check") { wallet.refresh() }
                    .buttonStyle(.borderedProminent)
                Button("Tools", action: reviewSetup)
                    .buttonStyle(.bordered)
            }
        }
        .padding(22)
        .detourLiquidGlass(cornerRadius: 26)
    }

    private var setupSurface: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Setup")
            setupStats
            LazyVStack(spacing: 10) {
                ForEach(sections.prefix(5)) { section in
                    setupSection(section)
                }
            }
            HStack {
                Button(applyingSetup ? "Checking..." : "Apply", action: applySetup)
                    .buttonStyle(.borderedProminent)
                    .disabled(applyingSetup)
                Button(runningScan ? "Scanning..." : "Scan this Mac", action: runScan)
                    .buttonStyle(.bordered)
                    .disabled(runningScan)
            }
        }
        .padding(22)
        .detourLiquidGlass(cornerRadius: 26)
    }

    private var setupStats: some View {
        HStack(spacing: 10) {
            metric("Selected", "\(summary.using)", "")
            metric("Verified", "\(summary.verified)", "")
            metric("Attention", "\(summary.needsAttention)", "")
        }
    }

    private func setupSection(_ section: DetourSetupInsightSection) -> some View {
        HStack(spacing: 12) {
            Text(section.title)
                .font(.headline)
            Spacer()
            Text("\(section.items.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let first = section.items.first {
                DetourHomeStatusPill(status: first.status)
            }
        }
        .padding(13)
        .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var commandComposer: some View {
        VStack(spacing: 10) {
            TextField("Ask Detour...", text: $command)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 54)
                .onSubmit(submitCommand)
            HStack {
                Button(action: openCanvas) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.68))
                    .help("OmniVoice")
                Spacer()
                Button(action: submitCommand) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: 820)
        .detourLiquidGlass(cornerRadius: 28, tint: Color(red: 0.03, green: 0.16, blue: 0.15).opacity(0.46))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color(red: 0.98, green: 0.72, blue: 0.38))
    }

    private func metric(_ title: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).lineLimit(1)
            if !detail.isEmpty {
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
    }

    private var socialItems: [DetourSetupInsightItem] {
        let needles = ["discord", "telegram", "imessage", "messages", "x account", "x session", "agentmail", "relationship"]
        var seen: Set<String> = []
        return sections.flatMap(\.items).filter { item in
            let value = [item.id, item.title, item.subtitle ?? "", item.detail, item.sourceLabel ?? ""]
                .joined(separator: " ")
                .lowercased()
            return needles.contains { value.contains($0) }
        }
        .filter { seen.insert($0.id).inserted }
    }

    private var agentName: String {
        store.agentName.isEmpty ? OnboardingStore.defaultAgentName : store.agentName
    }

}
