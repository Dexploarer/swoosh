// SwooshUI/DashboardPanes/ProviderConfigCard.swift — Provider configuration card controls — 0.9U

#if os(macOS)

import SwiftUI
import SwooshClient
import SwooshConfig
import SwooshCore
import SwooshGenerativeUI
import SwooshModels
import SwooshTools

struct ProviderConfigCard: View {
    @Environment(\.swooshTheme) var theme
    let provider: ProviderSummary
    let isActive: Bool
    let codexAuth: CodexAuthStatus?
    let onActivate: () async -> Void
    let onSaveAPIKey: (String) async -> Void
    let onStartCodexLogin: () async -> Void
    let onCancelCodexLogin: () async -> Void
    let onRefresh: () async -> Void

    @State private var draftKey: String = ""
    @State private var showKeyField = false
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            statusRow
            actionRow
            if showKeyField {
                apiKeyField
            }
            if provider.id == "codex" {
                codexFooter
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive ? theme.accent.opacity(0.06) : theme.textPrimary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            isActive ? theme.accent.opacity(0.4) : theme.textPrimary.opacity(0.08),
                            lineWidth: isActive ? 1.5 : 1
                        )
                )
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(providerColor.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: providerIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(providerColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(provider.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                    if isActive {
                        Text("ACTIVE")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.14)))
                            .overlay(Capsule().strokeBorder(Color.green.opacity(0.32), lineWidth: 0.5))
                    }
                }
                Text(blurb)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textPrimary.opacity(0.62))
                    .lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(costLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(costTint)
                Text(locationLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.textPrimary.opacity(0.5))
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Spacer(minLength: 8)
            if let model = provider.model, !model.isEmpty {
                Text(model)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.textPrimary.opacity(0.7))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(theme.textPrimary.opacity(0.06))
                    )
            }
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 8) {
            if !provider.configured {
                if provider.id == "codex" {
                    Button {
                        Task { busy = true; await onStartCodexLogin(); busy = false }
                    } label: {
                        Label(busy ? "Opening browser…" : "Sign in with ChatGPT",
                              systemImage: "person.badge.key.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.green)
                    .disabled(busy)
                } else if acceptsAPIKey {
                    Button {
                        withAnimation { showKeyField.toggle() }
                    } label: {
                        Label(showKeyField ? "Hide key field" : "Add API key", systemImage: "key.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if provider.id == ModelDefaults.localFoundationProviderID {
                    InfoChip(text: "Set SWOOSH_FOUNDATION_MODEL=1 on the daemon and restart.")
                } else if provider.id == ModelDefaults.localMLXProviderID {
                    InfoChip(text: "Runs Gemma 4/Qwen through mlx-swift-lm on Apple Silicon.")
                } else if provider.id == "local-openai" {
                    InfoChip(text: "Run a local Ollama server on 127.0.0.1:11434.")
                }
            }

            Spacer(minLength: 8)

            if !isActive {
                Button {
                    Task { busy = true; await onActivate(); busy = false }
                } label: {
                    Label(busy ? "Switching…" : "Use this provider", systemImage: "arrow.right.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(busy || !provider.configured)
            }
        }
    }

    private var apiKeyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            SecureField("Paste API key (sk-…)", text: $draftKey)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { showKeyField = false; draftKey = "" }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Save key") {
                    let k = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !k.isEmpty else { return }
                    Task {
                        busy = true
                        await onSaveAPIKey(k)
                        busy = false
                        showKeyField = false
                        draftKey = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
            }
            Text("Stored in the Mac Keychain under service `ai.swoosh.agent`. The agent will route through this provider on the next daemon restart.")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(theme.textPrimary.opacity(0.55))
        }
    }

    @ViewBuilder
    private var codexFooter: some View {
        if let auth = codexAuth, auth.state == .pending {
            VStack(alignment: .leading, spacing: 6) {
                Divider().opacity(0.2)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for browser auth…")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Button("Cancel") {
                        Task { await onCancelCodexLogin() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }
                if let url = auth.url {
                    Text(url)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textPrimary.opacity(0.6))
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
        } else if let auth = codexAuth, auth.state == .failed, let msg = auth.message {
            Divider().opacity(0.2)
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(msg).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textPrimary.opacity(0.7))
            }
        }
    }

    // MARK: Visual mappings

    private var acceptsAPIKey: Bool {
        DashboardProviderDisplay.acceptsAPIKey(providerID: provider.id)
    }

    private var providerIcon: String {
        switch provider.id {
        case "codex":            return "sparkles"
        case "openai":           return "circle.hexagongrid"
        case "openrouter":       return "arrow.triangle.branch"
        case ModelDefaults.localFoundationProviderID: return "apple.logo"
        case ModelDefaults.localMLXProviderID:        return "memorychip"
        case "local-openai":     return "server.rack"
        case "local-diagnostic": return "stethoscope"
        default:                 return "cloud"
        }
    }

    private var providerColor: Color {
        switch provider.id {
        case "codex":            return .green
        case "openai":           return .indigo
        case "openrouter":       return .orange
        case ModelDefaults.localFoundationProviderID: return .purple
        case ModelDefaults.localMLXProviderID:        return .blue
        case "local-openai":     return .teal
        case "local-diagnostic": return .gray
        default:                 return .secondary
        }
    }

    private var blurb: String {
        DashboardProviderDisplay.blurb(providerID: provider.id)
    }

    private var costLabel: String {
        DashboardProviderDisplay.costLabel(providerID: provider.id)
    }

    private var costTint: Color {
        switch provider.id {
        case "codex":            return .green
        case "openai", "openrouter": return .orange
        default:                 return .secondary
        }
    }

    private var locationLabel: String {
        DashboardProviderDisplay.locationLabel(providerID: provider.id)
    }

    private var statusColor: Color {
        if isActive { return .green }
        if provider.configured { return .blue }
        return .orange
    }

    private var statusLabel: String {
        DashboardProviderDisplay.statusLabel(for: provider.status)
    }
}

private struct InfoChip: View {
    @Environment(\.swooshTheme) var theme
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.textPrimary.opacity(0.55))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.textPrimary.opacity(0.7))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.textPrimary.opacity(0.05))
        )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Shared client builder
// ═══════════════════════════════════════════════════════════════════

#endif
