// SwooshUI/Dashboard/SafetyPane.swift — Agent permissions + safety flags — 0.9Y
//
// The control surface for what the agent is allowed to do. Loads
// GET /api/runtime/config and writes through POST /api/runtime/profile
// (permission preset) and POST /api/runtime/flags (the enforced safety
// knobs). These flags gate real decision points in ToolRegistry /
// SafetyConfig — this is live control, not a local preference.

#if os(macOS)
import SwiftUI
import SwooshGenerativeUI
import SwooshClient

public struct SafetyPane: View {
    @State private var profile: String = "developer"
    @State private var flags: [RuntimeFlagSummary] = []
    @State private var toolPolicy: ToolPolicySummary?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var requiresRestart = false
    @State private var busy: Set<String> = []
    @State private var profileBusy = false

    public init() {}

    private let presets: [(id: String, name: String, blurb: String)] = [
        ("safe", "Safe", "No shell, file writes, or app automation."),
        ("developer", "Developer", "File r/w in approved folders, shell with approval, Git, Xcode."),
        ("automation", "Automation", "Calendar, Reminders, Mail drafts, Shortcuts, workflows."),
        ("power", "Power", "Shell, browser, file writes, MCP. High-risk still needs approval."),
        ("trader", "Trader", "Mainnet trading with explicit human prompts to sign/broadcast."),
        ("autonomous", "Autonomous", "Full unattended operation; approval gates can be disabled."),
        ("custom", "Custom", "Hand-tuned permission set."),
    ]

    // Extra captions + high-risk styling for the flags the daemon emits.
    private let flagCaptions: [String: String] = [
        "modelSelfApprovalEnabled": "The agent approves its own tool calls — bypasses approval gates. Maximum autonomy, highest risk.",
        "mainnetWritesByDefault": "Allow mainnet writes without a per-action prompt.",
        "autonomousTradingEnabled": "Agent can trade without a human prompt.",
        "humanPromptedTradingEnabled": "Agent may trade when you explicitly ask it to.",
        "swapExecutionEnabled": "Allow token swaps to execute.",
        "shellToBlockchainBridgeEnabled": "Let shell command output feed blockchain actions.",
        "privateKeyCustodyEnabled": "Allow the agent to hold/sign with private keys in Keychain.",
        "seedPhraseIngestionEnabled": "Allow seed-phrase input (kept out of prompts).",
        "cookieIngestionEnabled": "Allow cookie ingestion for authenticated browsing.",
        "portfolioRecommendationsEnabled": "Allow AI portfolio analysis.",
    ]
    private let highRisk: Set<String> = [
        "modelSelfApprovalEnabled", "mainnetWritesByDefault",
        "autonomousTradingEnabled", "shellToBlockchainBridgeEnabled",
    ]

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if isLoading && flags.isEmpty {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(VoltPaper.destructive)
                } else {
                    presetSection
                    flagsSection
                    if let toolPolicy { policySection(toolPolicy) }
                }
            }
            .padding(24)
        }
        .background(SwooshNeonTokens.Canvas.bg)
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Agent & Safety")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                Spacer()
                Button { Task { await load() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                }
                .buttonStyle(.plain)
            }
            if requiresRestart {
                Label("Some changes take effect after the daemon restarts.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(VoltPaper.Chart.c4)
            } else if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            }
        }
    }

    // MARK: - Permission preset

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("PERMISSION PRESET")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(presets, id: \.id) { preset in
                    presetChip(preset)
                }
            }
            if let blurb = presets.first(where: { $0.id == profile })?.blurb {
                Text(blurb)
                    .font(.system(size: 11))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            }
        }
    }

    private func presetChip(_ preset: (id: String, name: String, blurb: String)) -> some View {
        let selected = profile == preset.id
        return Button { Task { await setProfile(preset.id) } } label: {
            HStack(spacing: 6) {
                Text(preset.name)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? VoltPaper.foreground : SwooshNeonTokens.Canvas.text2)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(VoltPaper.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? VoltPaper.accent.opacity(0.1) : VoltPaper.foreground.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? VoltPaper.accent.opacity(0.4) : VoltPaper.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(profileBusy)
    }

    // MARK: - Safety flags

    private var flagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("SAFETY FLAGS")
            ForEach(flags) { flag in
                flagRow(flag)
            }
        }
    }

    private func flagRow(_ flag: RuntimeFlagSummary) -> some View {
        let risky = highRisk.contains(flag.id)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(flag.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                    if risky {
                        Text("HIGH RISK")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(VoltPaper.destructive)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(VoltPaper.destructive.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                if let caption = flagCaptions[flag.id] {
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { flag.enabled },
                set: { newValue in Task { await setFlag(flag.id, newValue) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(risky ? VoltPaper.destructive : VoltPaper.accent)
            .disabled(busy.contains(flag.id))
        }
        .padding(12)
        .background(VoltPaper.foreground.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(risky ? VoltPaper.destructive.opacity(0.18) : SwooshNeonTokens.Line.rule, lineWidth: 0.5)
        )
    }

    // MARK: - Tool policy (read-only)

    private func policySection(_ p: ToolPolicySummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("TOOL POLICY (read-only)")
            HStack {
                policyBadge("Max calls/turn", "\(p.maxToolCallsPerTurn)")
                policyBadge("Max chain depth", "\(p.maxToolChainDepth)")
            }
            policyToggleBadge("Model tool calls", p.allowModelToolCalls)
            policyToggleBadge("humanOnly from model", p.allowHumanOnlyFromModel)
            policyToggleBadge("Critical tools from model", p.allowCriticalToolsFromModel)
            policyToggleBadge("Approve medium-risk and above", p.requireApprovalForMediumRiskAndAbove)
        }
    }

    private func policyBadge(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(SwooshNeonTokens.Canvas.text3)
            Text(value).foregroundStyle(SwooshNeonTokens.Canvas.text1).fontWeight(.semibold)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(VoltPaper.foreground.opacity(0.03))
        .clipShape(Capsule())
    }

    private func policyToggleBadge(_ label: String, _ on: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: on ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(on ? VoltPaper.accent : SwooshNeonTokens.Canvas.text3)
            Text(label).foregroundStyle(SwooshNeonTokens.Canvas.text2)
        }
        .font(.system(size: 11))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(SwooshNeonTokens.Canvas.text3)
    }

    // MARK: - Network

    private func apply(_ config: RuntimeConfigResponse) {
        profile = config.permissionProfile ?? "developer"
        flags = config.safetyFlags
        toolPolicy = config.toolPolicy
    }

    private func load() async {
        guard let client = SwooshDaemonClient.client() else {
            errorMessage = "Daemon not reachable."
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            apply(try await client.runtimeConfig())
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
        }
    }

    private func setProfile(_ id: String) async {
        guard id != profile, let client = SwooshDaemonClient.client() else { return }
        profileBusy = true
        defer { profileBusy = false }
        do {
            let result = try await client.updateRuntimeProfile(id)
            apply(result.config)
            requiresRestart = result.requiresRestart
            statusMessage = result.message
        } catch {
            statusMessage = "Update failed: \(error.localizedDescription)"
        }
    }

    private func setFlag(_ id: String, _ enabled: Bool) async {
        guard let client = SwooshDaemonClient.client() else { return }
        busy.insert(id)
        defer { busy.remove(id) }
        do {
            let result = try await client.updateRuntimeFlags([RuntimeFlagUpdate(id: id, enabled: enabled)])
            apply(result.config)
            requiresRestart = result.requiresRestart
            statusMessage = result.message
        } catch {
            statusMessage = "Update failed: \(error.localizedDescription)"
            await load()
        }
    }
}

#endif
