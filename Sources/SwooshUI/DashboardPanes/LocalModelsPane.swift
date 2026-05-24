// SwooshUI/DashboardPanes/LocalModelsPane.swift — Local model dashboard pane — 0.9U

#if os(macOS)

import SwiftUI
import SwooshClient
import SwooshConfig
import SwooshCore
import SwooshGenerativeUI
import SwooshModels
import SwooshTools

struct LocalModelsPane: View {
    let snapshot: DashboardRuntimeSnapshot
    @Environment(\.swooshTheme) var theme

    @State private var installed: [InstalledOllamaModel] = []
    @State private var trending: [DynamicModelLoader.TrendingModel] = []
    @State private var hardware: SwooshModels.HardwareProfile = .detectCurrent()
    @State private var pulling: String? = nil
    @State private var pullProgress: String = ""
    @State private var pullError: String? = nil
    @State private var isLoading = false

    init(snapshot: DashboardRuntimeSnapshot) {
        self.snapshot = snapshot
    }

    var body: some View {
        DashboardPane(
            title: "Local Models",
            icon: "cpu",
            subtitle: "On-device inference — runs entirely on your Mac"
        ) {
            HStack(spacing: 10) {
                StatBadge(value: hardware.chip, label: "Chip", tint: .blue)
                StatBadge(value: "\(Int(hardware.totalMemoryGB)) GB", label: "Memory", tint: .cyan)
                StatBadge(value: hardware.maxTier.rawValue.capitalized, label: "Max tier", tint: .purple)
                StatBadge(value: "\(installed.filter(\.isChatCapable).count)", label: "Chat models", tint: .green)
            }

            recommendedDefaultCard

            installedCard

            trendingCard

            providersCard
        }
        .task { await load() }
    }

    @ViewBuilder
    private var recommendedDefaultCard: some View {
        let recommendations = DynamicModelLoader.shared.recommendedLocalModels(hardware: hardware)
        PaneCard {
            sectionHeader("RECOMMENDED PULLS FOR YOUR HARDWARE")
            ForEach(recommendations) { model in
                let isInstalled = installed.contains { $0.name.hasPrefix(model.tag) }
                HStack(spacing: 12) {
                    Image(systemName: isInstalled ? "checkmark.seal.fill" : (model.isDefaultFallback ? "sparkles" : "terminal.fill"))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isInstalled ? .green : (model.isDefaultFallback ? .yellow : .cyan))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(model.tag)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(theme.textPrimary)
                            Text(model.isDefaultFallback ? "DEFAULT" : model.family.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(model.isDefaultFallback ? .yellow : .cyan)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill((model.isDefaultFallback ? Color.yellow : Color.cyan).opacity(0.14)))
                            if isInstalled {
                                Text("INSTALLED")
                                    .font(.system(size: 9, weight: .bold))
                                    .tracking(0.8)
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.green.opacity(0.14)))
                            }
                        }
                        Text("\(model.title) - \(model.reason) ~\(String(format: "%.1f", model.estimatedDiskGB)) GB download.")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(theme.textPrimary.opacity(0.65))
                    }
                    Spacer()
                    if !isInstalled {
                        Button {
                            Task { await pull(model.tag) }
                        } label: {
                            if pulling == model.tag {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Pulling...").font(.system(size: 12, weight: .semibold))
                                }
                            } else {
                                Label("Pull", systemImage: "arrow.down.circle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(model.isDefaultFallback ? .green : .cyan)
                        .disabled(pulling != nil)
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 10)

                if pulling == model.tag {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 12).padding(.bottom, 6)
                    Text(pullProgress.isEmpty ? "Downloading from Ollama..." : pullProgress)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textPrimary.opacity(0.6))
                        .padding(.horizontal, 12).padding(.bottom, 10)
                }
            }
            if let pullError {
                Text(pullError).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red).padding(.horizontal, 12).padding(.bottom, 10)
            }
        }
    }

    private var installedCard: some View {
        PaneCard {
            sectionHeader("INSTALLED VIA OLLAMA")
            if isLoading && installed.isEmpty {
                emptyRow(icon: "arrow.clockwise", text: "Querying Ollama…")
            } else if installed.isEmpty {
                emptyRow(icon: "tray", text: "No models installed yet. Use the Pull button above, or run `ollama pull <id>` in a terminal.")
            } else {
                ForEach(installed) { model in
                    ListRow(
                        icon: model.isChatCapable ? "checkmark.circle.fill" : "questionmark.circle",
                        iconTint: model.isChatCapable ? .green : .orange,
                        title: model.name,
                        subtitle: subtitleForInstalled(model),
                        trailing: formatSize(model.sizeBytes),
                        trailingTint: theme.textPrimary.opacity(0.7)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var trendingCard: some View {
        if !trending.isEmpty {
            PaneCard {
                sectionHeader("TRENDING ON HUGGING FACE (live)")
                ForEach(trending.prefix(8)) { model in
                    ListRow(
                        icon: "chart.line.uptrend.xyaxis",
                        iconTint: .orange,
                        title: model.id,
                        subtitle: trendingSubtitle(model),
                        trailing: model.downloads.map { formatDownloadCount($0) },
                        trailingTint: theme.textPrimary.opacity(0.65)
                    )
                }
            }
        }
    }

    private var providersCard: some View {
        PaneCard {
            sectionHeader("LOCAL INFERENCE BACKENDS")
            ListRow(
                icon: "apple.logo", iconTint: .purple,
                title: "Apple Foundation Models",
                subtitle: "On-device, free. Set SWOOSH_FOUNDATION_MODEL=1 on swooshd to enable.",
                trailing: snapshot.providers.first(where: { $0.id == ModelDefaults.localFoundationProviderID })?.configured == true ? "On" : "Off",
                trailingTint: snapshot.providers.first(where: { $0.id == ModelDefaults.localFoundationProviderID })?.configured == true ? .green : .secondary
            )
            ListRow(
                icon: "memorychip", iconTint: .blue,
                title: "MLX Local",
                subtitle: "Apple Silicon native inference through mlx-swift-lm.",
                trailing: snapshot.providers.first(where: { $0.id == ModelDefaults.localMLXProviderID })?.configured == true ? "On" : "Off",
                trailingTint: snapshot.providers.first(where: { $0.id == ModelDefaults.localMLXProviderID })?.configured == true ? .green : .secondary
            )
            ListRow(
                icon: "server.rack", iconTint: .teal,
                title: "Ollama",
                subtitle: "127.0.0.1:11434 · \(installed.count) model(s) on disk",
                trailing: installed.isEmpty ? "No models" : "Ready",
                trailingTint: installed.isEmpty ? .orange : .green
            )
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold))
            .tracking(1.4)
            .foregroundStyle(theme.textPrimary.opacity(0.55))
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
    }

    private func emptyRow(icon: String, text: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(theme.textPrimary.opacity(0.4))
                Text(text).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textPrimary.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(16)
    }

    private func subtitleForInstalled(_ m: InstalledOllamaModel) -> String {
        LocalModelDisplayFormatter.installedSubtitle(
            family: m.family,
            parameterSize: m.parameterSize,
            quantization: m.quantization,
            isChatCapable: m.isChatCapable
        )
    }

    private func trendingSubtitle(_ m: DynamicModelLoader.TrendingModel) -> String {
        let bits: [String?] = [m.pipelineTag, m.likes.map { "❤ \($0)" }]
        return bits.compactMap { $0 }.joined(separator: " · ")
    }

    private func formatDownloadCount(_ n: Int) -> String {
        LocalModelDisplayFormatter.formattedDownloadCount(n)
    }

    private func formatSize(_ bytes: Int64?) -> String? {
        LocalModelDisplayFormatter.formattedSize(bytes)
    }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        installed = await DynamicModelLoader.shared.installedOllamaModels()
        trending = await DynamicModelLoader.shared.trendingChatModels(limit: 8)
    }

    @MainActor
    private func pull(_ tag: String) async {
        pulling = tag
        pullError = nil
        defer { pulling = nil }

        var req = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/pull")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = "{\"name\":\"\(tag)\",\"stream\":true}".data(using: .utf8)

        do {
            let (bytes, _) = try await URLSession.shared.bytes(for: req)
            for try await line in bytes.lines {
                if let data = line.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let status = obj["status"] as? String ?? ""
                    if let total = obj["total"] as? Int, let completed = obj["completed"] as? Int, total > 0 {
                        pullProgress = "\(status) — \(Int(Double(completed) / Double(total) * 100))%"
                    } else {
                        pullProgress = status
                    }
                }
            }
            await load()
        } catch {
            pullError = error.localizedDescription
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - MCP
// ═══════════════════════════════════════════════════════════════════

#endif
