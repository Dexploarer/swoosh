// SwooshUI/Dashboard/ProvidersPane.swift — Capability-first model catalog — 0.9X
//
// Groups every model by what it CAN DO, not who provides it.
// Dense 4-column grid with compact cards. NSFW always visible
// as a clickable badge. Provider auth uses the correct flow per provider:
//   • OpenRouter — OAuth PKCE (browser redirect to openrouter.ai/auth)
//   • Codex      — OAuth device flow (startCodexAuth on daemon)
//   • OpenAI     — Manual key paste (link to platform.openai.com/api-keys)
//   • Detour Cloud — Manual key paste
//   • MLX Local  — No auth needed
//   • Ollama     — No auth needed

#if os(macOS)
import SwiftUI
import SwooshGenerativeUI
import SwooshClient
import SwooshModels
import AppKit

// ── Capability category (the grouping axis) ──────────────────────

private enum CapCategory: String, CaseIterable, Identifiable {
    case reasoning    = "Reasoning & Chat"
    case coding       = "Coding"
    case vision       = "Vision & OCR"
    case audio        = "Audio"
    case generation   = "Image & Video"
    case retrieval    = "Embeddings & Search"
    case agents       = "Agents & Gaming"
    case other        = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .reasoning:  return "brain.head.profile"
        case .coding:     return "chevron.left.forwardslash.chevron.right"
        case .vision:     return "eye"
        case .audio:      return "waveform"
        case .generation: return "paintbrush"
        case .retrieval:  return "magnifyingglass"
        case .agents:     return "gamecontroller"
        case .other:      return "ellipsis.circle"
        }
    }

    var color: Color {
        switch self {
        case .reasoning:  return SwooshNeonTokens.Accent.cyan
        case .coding:     return .green
        case .vision:     return .blue
        case .audio:      return .orange
        case .generation: return .pink
        case .retrieval:  return .purple
        case .agents:     return .red
        case .other:      return .gray
        }
    }

    static func primary(for entry: UnifiedModelEntry) -> CapCategory {
        let caps = entry.capabilities
        if caps.contains(.gaming)                                     { return .agents }
        if caps.contains(.imageGeneration) || caps.contains(.videoGeneration)
            || caps.contains(.imageEditing) || caps.contains(.musicGeneration) { return .generation }
        if caps.contains(.speechToText) || caps.contains(.textToSpeech)
            || caps.contains(.voiceCloning) || caps.contains(.vad)     { return .audio }
        if caps.contains(.vision) || caps.contains(.ocr)
            || caps.contains(.documentLayout)                          { return .vision }
        if caps.contains(.embedding) || caps.contains(.reranking)      { return .retrieval }
        if caps.contains(.coding) || caps.contains(.codeCompletion)    { return .coding }
        if caps.contains(.textGeneration) || caps.contains(.toolCalling) { return .reasoning }
        return .other
    }
}

public struct ProvidersPane: View {
    @State private var providerStatus: [ProviderSummary] = []
    @State private var activeProviderID: String?
    @State private var searchText = ""
    @State private var showNSFW = false
    @State private var selectedModelID: String?
    @State private var expandedCategory: CapCategory?
    @State private var hoveredModelID: String?

    // Codex auth
    @State private var codexAuthState: CodexAuthStatus.State = .idle
    @State private var codexAuthURL: String?
    @State private var codexAuthMessage: String?

    // OpenAI manual key
    @State private var showOpenAIKeySheet = false
    @State private var openAIKeyInput = ""

    // Detour Cloud manual key
    @State private var showDetourKeySheet = false
    @State private var detourKeyInput = ""

    public init() {}

    // ── Data ──────────────────────────────────────────────────────

    private var catalog: [UnifiedModelEntry] {
        showNSFW ? UnifiedModelCatalog.allIncludingNSFW : UnifiedModelCatalog.all
    }

    private var filtered: [UnifiedModelEntry] {
        guard !searchText.isEmpty else { return catalog }
        let q = searchText.lowercased()
        return catalog.filter {
            $0.displayName.lowercased().contains(q)
            || $0.family.lowercased().contains(q)
            || $0.modelID.lowercased().contains(q)
            || $0.providerID.lowercased().contains(q)
            || $0.blurb.lowercased().contains(q)
            || $0.capabilities.contains { $0.rawValue.lowercased().contains(q) }
        }
    }

    private var grouped: [(category: CapCategory, models: [UnifiedModelEntry])] {
        let dict = Dictionary(grouping: filtered, by: { CapCategory.primary(for: $0) })
        return CapCategory.allCases.compactMap { cat in
            guard let models = dict[cat], !models.isEmpty else { return nil }
            return (cat, models.sorted { $0.displayName < $1.displayName })
        }
    }

    private func providerSummary(_ id: String) -> ProviderSummary? {
        providerStatus.first { $0.id == id }
    }

    // ── Body ──────────────────────────────────────────────────────

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                providerConnectionCards
                capabilitySummaryBar
                ForEach(grouped, id: \.category) { group in
                    categorySection(group.category, models: group.models)
                }
            }
            .padding(24)
        }
        .background(SwooshNeonTokens.Canvas.bg)
        .task { await loadProviders() }
        .sheet(isPresented: $showOpenAIKeySheet) {
            apiKeySheet(providerName: "OpenAI", providerID: "openai", key: $openAIKeyInput, isPresented: $showOpenAIKeySheet)
        }
        .sheet(isPresented: $showDetourKeySheet) {
            apiKeySheet(providerName: "Detour Cloud", providerID: "detour-cloud", key: $detourKeyInput, isPresented: $showDetourKeySheet)
        }
    }

    // ── Header ────────────────────────────────────────────────────

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Models")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                    Text("\(catalog.count) models · \(grouped.count) categories")
                        .font(.system(size: 12))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                }
                Spacer()

                // NSFW toggle
                let nsfwCount = UnifiedModelCatalog.nsfwModels.count
                Button {
                    showNSFW.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 10))
                        Text("\(nsfwCount) NSFW")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(showNSFW ? .red : SwooshNeonTokens.Canvas.text3)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(showNSFW ? Color.red.opacity(0.12) : Color.white.opacity(0.04))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(showNSFW ? Color.red.opacity(0.3) : SwooshNeonTokens.Line.rule, lineWidth: 0.5))
                }
                .buttonStyle(.plain)

                Button { Task { await loadProviders() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                }
                .buttonStyle(.plain)
            }

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                    .font(.system(size: 12))
                TextField("Search models, capabilities, providers…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(SwooshNeonTokens.Line.rule, lineWidth: 0.5)
            )
        }
    }

    // ══════════════════════════════════════════════════════════════
    // MARK: - Provider Connection Cards
    // ══════════════════════════════════════════════════════════════

    private var providerConnectionCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Providers")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SwooshNeonTokens.Canvas.text1)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ], spacing: 10) {
                // OpenRouter — OAuth PKCE
                providerCard(
                    id: "openrouter",
                    name: "OpenRouter",
                    icon: "globe",
                    color: .purple,
                    authLabel: "Sign In",
                    authDescription: "OAuth — opens browser"
                ) {
                    startOpenRouterOAuth()
                }

                // Codex — OAuth device flow
                providerCard(
                    id: "codex",
                    name: "Codex (ChatGPT)",
                    icon: "sparkles",
                    color: .green,
                    authLabel: codexAuthState == .pending ? "Signing in…" : "Sign In",
                    authDescription: "OAuth — opens browser"
                ) {
                    Task { await startCodexAuth() }
                }

                // OpenAI — manual key paste
                providerCard(
                    id: "openai",
                    name: "OpenAI API",
                    icon: "key",
                    color: .blue,
                    authLabel: "Add Key",
                    authDescription: "Paste from platform.openai.com"
                ) {
                    openAIKeyInput = ""
                    showOpenAIKeySheet = true
                }

                // Detour Cloud
                providerCard(
                    id: "detour-cloud",
                    name: "Detour Cloud",
                    icon: "cloud",
                    color: SwooshNeonTokens.Accent.cyan,
                    authLabel: "Add Key",
                    authDescription: "Paste API key"
                ) {
                    detourKeyInput = ""
                    showDetourKeySheet = true
                }

                // MLX Local — no auth
                providerCard(
                    id: "mlx-local",
                    name: "MLX Local",
                    icon: "desktopcomputer",
                    color: .orange,
                    authLabel: nil,
                    authDescription: "On-device · no key needed"
                ) {}

                // Ollama
                providerCard(
                    id: "local-openai",
                    name: "Ollama / Local",
                    icon: "server.rack",
                    color: .gray,
                    authLabel: nil,
                    authDescription: "Connects to localhost:11434"
                ) {}
            }

            // Codex auth status banner
            if codexAuthState == .pending, let url = codexAuthURL {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Codex sign-in pending")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                        Text("If the browser didn't open, visit:")
                            .font(.system(size: 9))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                        Text(url)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.blue)
                            .onTapGesture {
                                if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                            }
                    }
                    Spacer()
                    Button("Cancel") {
                        Task { await cancelCodexAuth() }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .font(.system(size: 10, weight: .medium))
                }
                .padding(10)
                .background(Color.green.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.green.opacity(0.2), lineWidth: 0.5)
                )
            }
        }
    }

    private func providerCard(
        id: String,
        name: String,
        icon: String,
        color: Color,
        authLabel: String?,
        authDescription: String,
        action: @escaping () -> Void
    ) -> some View {
        let status = providerSummary(id)
        let isActive = activeProviderID == id
        let isConfigured = status?.configured ?? false

        return HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                        .lineLimit(1)
                    if isActive {
                        Text("ACTIVE")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                Text(authDescription)
                    .font(.system(size: 9))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                    .lineLimit(1)
            }

            Spacer()

            if isConfigured {
                // Connected state
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                        .shadow(color: .green.opacity(0.4), radius: 2)
                    Text("Connected")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.green)
                }
                // Set Active button if not already active
                if !isActive {
                    Button {
                        Task { await selectProvider(id) }
                    } label: {
                        Text("Use")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(color.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            } else if let label = authLabel {
                // Not connected — show auth button
                Button(action: action) {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(color.gradient)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive ? color.opacity(0.04) : Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isActive ? color.opacity(0.3) : SwooshNeonTokens.Line.rule,
                    lineWidth: isActive ? 1 : 0.5
                )
        )
    }

    // ── API Key Sheet (for OpenAI and Detour Cloud) ──────────────

    private func apiKeySheet(
        providerName: String,
        providerID: String,
        key: Binding<String>,
        isPresented: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Connect \(providerName)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                Spacer()
                Button { isPresented.wrappedValue = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                }
                .buttonStyle(.plain)
            }

            if providerID == "openai" {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                    Text("Get your key from")
                        .font(.system(size: 12))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                    Text("platform.openai.com/api-keys")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.blue)
                        .onTapGesture {
                            if let url = URL(string: "https://platform.openai.com/api-keys") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("API Key")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                SecureField("sk-...", text: key)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented.wrappedValue = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                Button {
                    Task {
                        await saveKey(providerID: providerID, key: key.wrappedValue)
                        isPresented.wrappedValue = false
                    }
                } label: {
                    Text("Connect")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.blue.gradient)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(key.wrappedValue.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    // ── Capability summary bar ────────────────────────────────────

    private var capabilitySummaryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(grouped, id: \.category) { group in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            expandedCategory = expandedCategory == group.category ? nil : group.category
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: group.category.icon)
                                .font(.system(size: 11))
                                .foregroundStyle(group.category.color)
                            Text("\(group.models.count)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                            Text(group.category.rawValue)
                                .font(.system(size: 10))
                                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            expandedCategory == group.category
                                ? group.category.color.opacity(0.12)
                                : group.category.color.opacity(0.05)
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().strokeBorder(
                                expandedCategory == group.category
                                    ? group.category.color.opacity(0.4)
                                    : Color.clear,
                                lineWidth: 1
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // ── Category section ──────────────────────────────────────────

    private func categorySection(_ cat: CapCategory, models: [UnifiedModelEntry]) -> some View {
        let isCollapsed = expandedCategory != nil && expandedCategory != cat

        return VStack(alignment: .leading, spacing: 10) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: cat.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(cat.color)
                    .frame(width: 24, height: 24)
                    .background(cat.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(cat.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                Text("(\(models.count))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                Rectangle().fill(cat.color.opacity(0.15)).frame(height: 1)
            }

            if !isCollapsed {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                ], spacing: 8) {
                    ForEach(models) { entry in
                        modelCard(entry, accentColor: cat.color)
                    }
                }
            }
        }
        .opacity(isCollapsed ? 0.4 : 1)
        .animation(.easeInOut(duration: 0.2), value: isCollapsed)
    }

    // ── Model card (compact, dense) ───────────────────────────────

    private func modelCard(_ entry: UnifiedModelEntry, accentColor: Color) -> some View {
        let isHovered = hoveredModelID == entry.id
        let isSelected = selectedModelID == entry.id
        let isNSFW = entry.contentRating == .nsfw

        return VStack(alignment: .leading, spacing: 5) {
            // Row 1: runtime badge + provider
            HStack(spacing: 4) {
                runtimeDot(entry.runtime)
                Text(providerTag(entry.providerID))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                    .lineLimit(1)
                Spacer()
                if isNSFW {
                    Text("18+")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.red.opacity(0.15))
                        .clipShape(Capsule())
                }
                if entry.isLoRA {
                    Text("LoRA")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            // Row 2: name
            Text(entry.displayName.replacingOccurrences(of: " ⛓️\u{200d}💥", with: ""))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                .lineLimit(1)

            // Row 3: blurb (only on hover or selected)
            if (isHovered || isSelected) && !entry.blurb.isEmpty {
                Text(entry.blurb)
                    .font(.system(size: 9))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                    .lineLimit(2)
                    .transition(.opacity)
            }

            // Row 4: stats
            HStack(spacing: 3) {
                if let ctx = entry.contextWindow {
                    statTag("\(ctx / 1000)k", color: accentColor)
                }
                if let mem = entry.estimatedMemoryGB {
                    statTag("\(String(format: "%.0f", mem))G", color: memColor(mem))
                }
                Spacer()
                // Top 3 capability dots
                HStack(spacing: 2) {
                    ForEach(Array(entry.capabilities.prefix(3)), id: \.self) { cap in
                        Text(capEmoji(cap))
                            .font(.system(size: 8))
                            .help(cap.rawValue)
                    }
                    if entry.capabilities.count > 3 {
                        Text("+\(entry.capabilities.count - 3)")
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                    }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? accentColor.opacity(0.08) : (isHovered ? Color.white.opacity(0.04) : Color.white.opacity(0.02)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isSelected ? accentColor.opacity(0.5) : (isHovered ? SwooshNeonTokens.Line.rule : SwooshNeonTokens.Line.rule.opacity(0.3)),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        )
        .onTapGesture { selectedModelID = entry.id }
        .onHover { hoveredModelID = $0 ? entry.id : nil }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    // ── Small helpers ─────────────────────────────────────────────

    private func runtimeDot(_ runtime: ModelRuntimeKind) -> some View {
        let (label, color): (String, Color) = switch runtime {
        case .router, .codex, .openAI, .openRouter, .detourCloud: ("☁", SwooshNeonTokens.Accent.cyan)
        case .localMLX:       ("M", Color.purple)
        case .localOpenAI:    ("O", .orange)
        case .localFoundation:("A", .gray)
        case .localLiteRT:    ("L", .green)
        }
        return Text(label)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 14, height: 14)
            .background(color.opacity(0.12))
            .clipShape(Circle())
    }

    private func statTag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    private func providerTag(_ pid: String) -> String {
        switch pid {
        case "codex": return "Codex"
        case "openai": return "OpenAI"
        case "openrouter": return "OpenRouter"
        case "detour-cloud": return "Detour"
        case "mlx-local": return "MLX"
        case "local-openai": return "Ollama"
        case "apple-foundation": return "Apple"
        case "litert-local": return "LiteRT"
        default: return pid
        }
    }

    private func memColor(_ gb: Double) -> Color {
        switch gb {
        case ..<4: return .green
        case ..<10: return .orange
        default: return .red
        }
    }

    private func capEmoji(_ cap: ModelCapability) -> String {
        switch cap {
        case .textGeneration: return "💬"
        case .coding, .codeCompletion: return "🖥️"
        case .vision, .imageClassification: return "👁️"
        case .toolCalling: return "🔧"
        case .structuredOutput: return "📋"
        case .embedding: return "📐"
        case .speechToText: return "🎤"
        case .textToSpeech: return "🔊"
        case .imageGeneration: return "🎨"
        case .reranking: return "🔀"
        case .ocr, .documentLayout: return "📷"
        case .gaming: return "🎮"
        case .videoGeneration: return "🎬"
        case .musicGeneration: return "🎵"
        case .threeD, .worldGeneration, .threeDReconstruction: return "🧊"
        default: return "⚡"
        }
    }

    // ══════════════════════════════════════════════════════════════
    // MARK: - Auth Actions
    // ══════════════════════════════════════════════════════════════

    /// OpenRouter OAuth PKCE — opens browser to openrouter.ai/auth
    private func startOpenRouterOAuth() {
        // The callback URL needs to be something the daemon can handle.
        // For now, open the OpenRouter auth page with the daemon's callback.
        let callbackURL = "https://openrouter.ai/auth?callback_url=http://127.0.0.1:8787/api/providers/openrouter/callback"
        if let url = URL(string: callbackURL) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Codex OAuth — delegates to the daemon's device flow
    private func startCodexAuth() async {
        guard let client = SwooshDaemonClient.client() else { return }
        do {
            let status = try await client.startCodexAuth()
            codexAuthState = status.state
            codexAuthURL = status.url
            codexAuthMessage = status.message
            // If there's a URL, open it
            if let urlStr = status.url, let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
            }
            // Poll for completion
            Task { await pollCodexAuth() }
        } catch {
            codexAuthState = .failed
            codexAuthMessage = error.localizedDescription
        }
    }

    private func cancelCodexAuth() async {
        guard let client = SwooshDaemonClient.client() else { return }
        do {
            let status = try await client.cancelCodexAuth()
            codexAuthState = status.state
        } catch {}
    }

    private func pollCodexAuth() async {
        guard let client = SwooshDaemonClient.client() else { return }
        for _ in 0..<60 {  // poll for up to 2 minutes
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            do {
                let status = try await client.codexAuthStatus()
                codexAuthState = status.state
                codexAuthURL = status.url
                codexAuthMessage = status.message
                if status.state == .signedIn || status.state == .failed || status.state == .cancelled {
                    await loadProviders()
                    return
                }
            } catch {
                return
            }
        }
    }

    // ── Network ───────────────────────────────────────────────────

    private func loadProviders() async {
        guard let client = SwooshDaemonClient.client() else { return }
        do {
            let response = try await client.providers()
            providerStatus = response.providers
            activeProviderID = response.activeProviderID
        } catch {
            // Offline — just show catalog
        }
    }

    private func saveKey(providerID: String, key: String) async {
        guard let client = SwooshDaemonClient.client() else { return }
        do {
            _ = try await client.saveProviderKey(providerID: providerID, apiKey: key)
            await loadProviders()
        } catch {}
    }

    private func selectProvider(_ id: String) async {
        guard let client = SwooshDaemonClient.client() else { return }
        do {
            _ = try await client.selectProvider(providerID: id)
            await loadProviders()
        } catch {}
    }
}

#endif
