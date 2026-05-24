// SwooshUI/DashboardPanes/DashboardInspectorPane.swift — Workspace inspector rail — 0.9V

#if os(macOS)

import SwiftUI
import SwooshGenerativeUI

struct DashboardInspectorPane: View {
    let selectedTab: DashboardTab
    let runtime: DashboardRuntimeSnapshot
    let layout: PanelLayout
    @Binding var editingPanels: Bool
    let onApplyPreset: (PanelLayoutPreset) -> Void
    let onResetLayout: () -> Void
    let onSelectTab: (DashboardTab) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                selectedSurfaceCard
                runtimeCard
                layoutCard
                actionsCard
                safetyCard
            }
            .padding(14)
        }
        .frame(minWidth: 280, idealWidth: 310, maxWidth: 340)
        .background(SwooshNeonTokens.Canvas.bg)
    }

    private var selectedSurfaceCard: some View {
        InspectorCard(accent: selectedTab.inspectorAccent) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selectedTab.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selectedTab.inspectorAccent.color)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 5) {
                    Text(selectedTab.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                    Text(selectedTab.inspectorSummary)
                        .font(.system(size: 12))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var runtimeCard: some View {
        InspectorCard(title: "Live State", systemImage: "waveform.path.ecg", accent: .cyan) {
            VStack(spacing: 8) {
                InspectorMetricRow(
                    title: "Daemon",
                    value: runtime.daemonReachable ? "Reachable" : "Offline",
                    systemImage: "network",
                    tint: runtime.daemonReachable ? SwooshNeonTokens.Accent.green : SwooshNeonTokens.Accent.gold
                )
                InspectorMetricRow(
                    title: "Readiness",
                    value: runtime.readiness.state.rawValue.capitalized,
                    systemImage: "checkmark.seal",
                    tint: runtime.readinessLevelColor
                )
                InspectorMetricRow(
                    title: "Approvals",
                    value: "\(runtime.pendingApprovalCount)",
                    systemImage: "hand.raised",
                    tint: runtime.pendingApprovalCount == 0 ? SwooshNeonTokens.Canvas.text2 : SwooshNeonTokens.Accent.gold
                )
                InspectorMetricRow(
                    title: "Panels",
                    value: "\(layout.panels.count)",
                    systemImage: "square.grid.2x2",
                    tint: SwooshNeonTokens.Accent.cyan
                )
            }
        }
    }

    private var layoutCard: some View {
        InspectorCard(title: "Workspace Layout", systemImage: "slider.horizontal.3", accent: .cyan) {
            VStack(alignment: .leading, spacing: 10) {
                Menu {
                    ForEach(PanelLayoutPreset.options(for: layout.surface)) { preset in
                        Button {
                            onApplyPreset(preset)
                        } label: {
                            Label(preset.name, systemImage: preset.systemImage)
                        }
                    }
                } label: {
                    Label("Apply Preset", systemImage: "rectangle.3.group")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    withAnimation(.spring(duration: 0.2)) {
                        editingPanels.toggle()
                    }
                } label: {
                    Label(editingPanels ? "Done Customizing" : "Customize Panels",
                          systemImage: editingPanels ? "checkmark.circle.fill" : "square.grid.2x2")
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    onResetLayout()
                } label: {
                    Label("Reset Layout", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12, weight: .semibold))
        }
    }

    private var actionsCard: some View {
        InspectorCard(title: "Next Actions", systemImage: "arrow.up.forward.circle", accent: .green) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(selectedTab.inspectorActions) { action in
                    Button {
                        onSelectTab(action.target)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .font(.system(size: 12, weight: .semibold))
        }
    }

    private var safetyCard: some View {
        InspectorCard(title: "Safety", systemImage: "shield.checkered", accent: .gold) {
            VStack(spacing: 8) {
                InspectorMetricRow(
                    title: "Human-only",
                    value: runtime.runtimeConfig?.toolPolicy.allowHumanOnlyFromModel == true ? "Allowed" : "Blocked",
                    systemImage: "hand.raised",
                    tint: runtime.runtimeConfig?.toolPolicy.allowHumanOnlyFromModel == true ? SwooshNeonTokens.Accent.gold : SwooshNeonTokens.Accent.green
                )
                InspectorMetricRow(
                    title: "Critical tools",
                    value: runtime.runtimeConfig?.toolPolicy.allowCriticalToolsFromModel == true ? "Allowed" : "Blocked",
                    systemImage: "exclamationmark.triangle",
                    tint: runtime.runtimeConfig?.toolPolicy.allowCriticalToolsFromModel == true ? SwooshNeonTokens.Accent.gold : SwooshNeonTokens.Accent.green
                )
                InspectorMetricRow(
                    title: "Medium risk",
                    value: runtime.runtimeConfig?.toolPolicy.requireApprovalForMediumRiskAndAbove == false ? "Optional" : "Approval",
                    systemImage: "checkmark.seal",
                    tint: runtime.runtimeConfig?.toolPolicy.requireApprovalForMediumRiskAndAbove == false ? SwooshNeonTokens.Accent.gold : SwooshNeonTokens.Accent.green
                )
            }
        }
    }
}

private struct InspectorCard<Content: View>: View {
    let title: String?
    let systemImage: String?
    let accent: NeonAccent
    let content: () -> Content

    init(
        title: String? = nil,
        systemImage: String? = nil,
        accent: NeonAccent = .cyan,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accent = accent
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title, let systemImage {
                Label(title.uppercased(), systemImage: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neonTile(accent, state: .idle, shape: .card)
    }
}

private struct InspectorMetricRow: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(SwooshNeonTokens.Canvas.text2)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
        }
    }
}

private struct DashboardInspectorAction: Identifiable {
    let id: DashboardTab
    let title: String
    let systemImage: String
    let target: DashboardTab

    init(_ title: String, systemImage: String, target: DashboardTab) {
        self.id = target
        self.title = title
        self.systemImage = systemImage
        self.target = target
    }
}

private extension DashboardRuntimeSnapshot {
    var readinessLevelColor: Color {
        switch readiness.state {
        case .ready:
            return SwooshNeonTokens.Accent.green
        case .degraded, .blocked:
            return SwooshNeonTokens.Accent.gold
        }
    }
}

private extension DashboardTab {
    var inspectorAccent: NeonAccent {
        switch self {
        case .wallet, .trading, .jupiter, .defi, .launchpads:
            return .green
        case .approvals, .firewall, .secrets, .manifesting:
            return .gold
        default:
            return .cyan
        }
    }

    var inspectorSummary: String {
        switch self {
        case .workspace:
            return "Arrange the command center around active agent work, approvals, runtime state, and saved surfaces."
        case .chat:
            return "Direct conversation surface with model selection, voice state, attachments, and generated UI."
        case .voice:
            return "Speech capture, playback, voice mode, and desktop projection controls."
        case .generative:
            return "Agent-emitted UI surfaces rendered through the registered component catalog."
        case .agents:
            return "Kernel, provider, model, and active agent runtime status."
        case .board, .workflows, .triggers, .goals:
            return "Work execution state, replayable flows, triggers, and goal iterations."
        case .manifesting:
            return "Background self-improvement passes and proposal review."
        case .vault, .skills, .scout, .spotlight:
            return "Knowledge surfaces: approved memory, trusted skills, personalization sources, and system search."
        case .wallet, .trading, .jupiter, .defi, .launchpads:
            return "Value surfaces for wallet state, trading capability, and market integrations."
        case .tools, .firewall, .secrets, .providers, .localModels, .mcp, .plugins, .chatAdapters, .media:
            return "System capability surfaces for tools, permissions, providers, models, plugins, and media."
        case .approvals, .auditLog, .usage, .costs, .traces, .benchmarks:
            return "Observation surfaces for human gates, audit trails, spend, usage, traces, and benchmarks."
        case .appearance:
            return "Live theme, motion, glass, and visual customization."
        case .settings:
            return "Runtime configuration, tool policy, safety flags, and readiness."
        }
    }

    var inspectorActions: [DashboardInspectorAction] {
        switch self {
        case .workspace:
            return [
                DashboardInspectorAction("Open Chat", systemImage: "bubble.left.and.bubble.right", target: .chat),
                DashboardInspectorAction("Review Approvals", systemImage: "hand.raised", target: .approvals),
                DashboardInspectorAction("Check Models", systemImage: "cpu", target: .localModels)
            ]
        case .chat, .voice, .generative:
            return [
                DashboardInspectorAction("Open Workspace", systemImage: "square.grid.2x2", target: .workspace),
                DashboardInspectorAction("Open Voice", systemImage: "mic.circle", target: .voice),
                DashboardInspectorAction("Open Surfaces", systemImage: "rectangle.on.rectangle.angled", target: .generative)
            ]
        case .wallet, .trading, .jupiter, .defi, .launchpads:
            return [
                DashboardInspectorAction("Open Wallet", systemImage: "creditcard", target: .wallet),
                DashboardInspectorAction("Trading Gates", systemImage: "shield.checkered", target: .firewall),
                DashboardInspectorAction("Audit Actions", systemImage: "list.bullet.rectangle", target: .auditLog)
            ]
        case .approvals, .auditLog, .usage, .costs, .traces, .benchmarks:
            return [
                DashboardInspectorAction("Review Approvals", systemImage: "hand.raised", target: .approvals),
                DashboardInspectorAction("Open Audit", systemImage: "list.bullet.rectangle", target: .auditLog),
                DashboardInspectorAction("Open Traces", systemImage: "point.3.connected.trianglepath.dotted", target: .traces)
            ]
        default:
            return [
                DashboardInspectorAction("Open Workspace", systemImage: "square.grid.2x2", target: .workspace),
                DashboardInspectorAction("Open Providers", systemImage: "cloud", target: .providers),
                DashboardInspectorAction("Open Settings", systemImage: "gear", target: .settings)
            ]
        }
    }
}

#endif
