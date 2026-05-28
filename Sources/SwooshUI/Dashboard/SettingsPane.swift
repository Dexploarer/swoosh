// SwooshUI/Dashboard/SettingsPane.swift — Settings page in the dashboard
//
// Top-level settings: appearance, providers, permissions, about.

#if os(macOS)

import SwiftUI
import SwooshGenerativeUI

public struct SettingsPane: View {
    @AppStorage("swoosh.appearance.theme") private var themeName: String = "midnight"
    @AppStorage("swoosh.appearance.accentColor") private var accentName: String = "cyan"
    @AppStorage("swoosh.daemon.autostart") private var autostart: Bool = true
    @AppStorage("swoosh.daemon.port") private var port: Int = 9099
    @AppStorage("swoosh.scout.personalisation") private var personalisationDepth: String = "standard"

    // ── Provider settings ─────────────────────────────────────────
    @AppStorage("swoosh.provider.openai.enabled") private var openAIEnabled: Bool = false
    @AppStorage("swoosh.provider.openai.model") private var openAIModel: String = "gpt-4o"
    @AppStorage("swoosh.provider.openai.key") private var openAIKey: String = ""

    @AppStorage("swoosh.provider.openrouter.enabled") private var openRouterEnabled: Bool = false
    @AppStorage("swoosh.provider.openrouter.model") private var openRouterModel: String = "anthropic/claude-sonnet-4"
    @AppStorage("swoosh.provider.openrouter.key") private var openRouterKey: String = ""

    @AppStorage("swoosh.provider.detourcloud.enabled") private var detourCloudEnabled: Bool = false
    @AppStorage("swoosh.provider.detourcloud.model") private var detourCloudModel: String = "detour-cloud-v1"
    @AppStorage("swoosh.provider.detourcloud.key") private var detourCloudKey: String = ""

    @AppStorage("swoosh.provider.local.enabled") private var localEnabled: Bool = false
    @AppStorage("swoosh.provider.local.model") private var localModel: String = "llama3.3"
    @AppStorage("swoosh.provider.local.baseURL") private var localBaseURL: String = "http://127.0.0.1:11434/v1"

    @AppStorage("swoosh.provider.mlx.enabled") private var mlxEnabled: Bool = false
    @AppStorage("swoosh.provider.mlx.model") private var mlxModel: String = "mlx-community/Llama-3.3-70B"

    @AppStorage("swoosh.provider.codex.enabled") private var codexEnabled: Bool = false
    @AppStorage("swoosh.provider.codex.model") private var codexModel: String = "codex"

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Title
                Text("Settings")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                    .padding(.bottom, 28)

                // ── Appearance ───────────────────────────────
                sectionHeader("Appearance")

                cardGroup {
                    settingRow(icon: "paintpalette", title: "Theme") {
                        Picker("", selection: $themeName) {
                            Text("Midnight").tag("midnight")
                            Text("Charcoal").tag("charcoal")
                            Text("OLED Black").tag("oled")
                            Text("Light").tag("light")
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }

                    cardDivider

                    settingRow(icon: "circle.fill", title: "Accent colour") {
                        Picker("", selection: $accentName) {
                            Text("Cyan").tag("cyan")
                            Text("Purple").tag("purple")
                            Text("Green").tag("green")
                            Text("Orange").tag("orange")
                            Text("Pink").tag("pink")
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                }

                // ── Daemon ──────────────────────────────────
                sectionHeader("Daemon")
                    .padding(.top, 24)

                cardGroup {
                    settingRow(icon: "bolt.fill", title: "Start at login") {
                        Toggle("", isOn: $autostart)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }

                    cardDivider

                    settingRow(icon: "network", title: "Port") {
                        TextField("", value: $port, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                }

                // ── Personalisation ─────────────────────────
                sectionHeader("Personalisation")
                    .padding(.top, 24)

                cardGroup {
                    settingRow(icon: "person.and.background.dotted", title: "Scout depth") {
                        Picker("", selection: $personalisationDepth) {
                            Text("Minimal").tag("minimal")
                            Text("Standard").tag("standard")
                            Text("Deep").tag("deep")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                }

                // ── Providers ───────────────────────────────
                sectionHeader("Providers")
                    .padding(.top, 24)

                providerCard(
                    icon: "brain.head.profile",
                    name: "OpenAI API",
                    detail: "GPT-4o, o3, o4-mini — direct API",
                    isEnabled: $openAIEnabled,
                    model: $openAIModel,
                    apiKey: $openAIKey,
                    baseURL: nil
                )

                providerCard(
                    icon: "arrow.triangle.branch",
                    name: "OpenRouter",
                    detail: "Claude, Gemini, Llama, Mistral — multi-model gateway",
                    isEnabled: $openRouterEnabled,
                    model: $openRouterModel,
                    apiKey: $openRouterKey,
                    baseURL: nil
                )
                .padding(.top, 8)

                providerCard(
                    icon: "cloud.fill",
                    name: "Detour Cloud",
                    detail: "Hosted inference with $DTOUR affiliate revenue",
                    isEnabled: $detourCloudEnabled,
                    model: $detourCloudModel,
                    apiKey: $detourCloudKey,
                    baseURL: nil
                )
                .padding(.top, 8)

                providerCard(
                    icon: "desktopcomputer",
                    name: "Local (Ollama / LM Studio / vLLM)",
                    detail: "Any OpenAI-compatible server on localhost",
                    isEnabled: $localEnabled,
                    model: $localModel,
                    apiKey: nil,
                    baseURL: $localBaseURL
                )
                .padding(.top, 8)

                providerCard(
                    icon: "apple.logo",
                    name: "MLX Local",
                    detail: "Apple Silicon on-device — MLXLLM / MLXVLM",
                    isEnabled: $mlxEnabled,
                    model: $mlxModel,
                    apiKey: nil,
                    baseURL: nil
                )
                .padding(.top, 8)

                providerCard(
                    icon: "terminal.fill",
                    name: "ChatGPT (via Codex CLI)",
                    detail: "Bridge through installed Codex CLI binary",
                    isEnabled: $codexEnabled,
                    model: $codexModel,
                    apiKey: nil,
                    baseURL: nil
                )
                .padding(.top, 8)

                // ── About ───────────────────────────────────
                sectionHeader("About")
                    .padding(.top, 24)

                cardGroup {
                    HStack(spacing: 12) {
                        Image(systemName: "app.badge.checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Detour Agent")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                            Text("v0.9R · macOS 26 · Swift 6.3")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }

                Spacer(minLength: 40)
            }
            .padding(32)
            .frame(maxWidth: 640, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SwooshNeonTokens.Canvas.bg)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9.5, weight: .bold))
            .tracking(1.6)
            .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            .padding(.bottom, 10)
    }

    @ViewBuilder
    private func cardGroup(@ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SwooshNeonTokens.Canvas.text1.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(SwooshNeonTokens.Line.rule, lineWidth: 0.5)
                )
        )
    }

    private var cardDivider: some View {
        Rectangle()
            .fill(SwooshNeonTokens.Line.rule)
            .frame(height: 0.5)
            .padding(.leading, 44)
    }

    @ViewBuilder
    private func providerCard(
        icon: String,
        name: String,
        detail: String,
        isEnabled: Binding<Bool>,
        model: Binding<String>,
        apiKey: Binding<String>?,
        baseURL: Binding<String>?
    ) -> some View {
        VStack(spacing: 0) {
            // Header row
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isEnabled.wrappedValue ? SwooshNeonTokens.Accent.cyan : SwooshNeonTokens.Canvas.text3)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                    Text(detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Toggle("", isOn: isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            // Expanded config when enabled
            if isEnabled.wrappedValue {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(SwooshNeonTokens.Line.rule)
                        .frame(height: 0.5)
                        .padding(.leading, 44)

                    // Model
                    HStack(spacing: 12) {
                        Image(systemName: "cpu")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                            .frame(width: 24)
                        Text("Model")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                        Spacer(minLength: 12)
                        TextField("model-id", text: model)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                    // API Key (if applicable)
                    if let apiKey {
                        Rectangle()
                            .fill(SwooshNeonTokens.Line.rule)
                            .frame(height: 0.5)
                            .padding(.leading, 44)

                        HStack(spacing: 12) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                                .frame(width: 24)
                            Text("API Key")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                            Spacer(minLength: 12)
                            SecureField("sk-•••", text: apiKey)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }

                    // Base URL (if applicable)
                    if let baseURL {
                        Rectangle()
                            .fill(SwooshNeonTokens.Line.rule)
                            .frame(height: 0.5)
                            .padding(.leading, 44)

                        HStack(spacing: 12) {
                            Image(systemName: "link")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                                .frame(width: 24)
                            Text("Base URL")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                            Spacer(minLength: 12)
                            TextField("http://127.0.0.1:11434/v1", text: baseURL)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SwooshNeonTokens.Canvas.text1.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            isEnabled.wrappedValue ? SwooshNeonTokens.Accent.cyan.opacity(0.3) : SwooshNeonTokens.Line.rule,
                            lineWidth: 0.5
                        )
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isEnabled.wrappedValue)
    }

    @ViewBuilder
    private func settingRow(icon: String, title: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                .frame(width: 22)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SwooshNeonTokens.Canvas.text1)

            Spacer(minLength: 12)

            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

#endif
