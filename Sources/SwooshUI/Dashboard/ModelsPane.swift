// SwooshUI/Dashboard/ModelsPane.swift — Full model catalog browser — 0.9V
//
// Reads from UnifiedModelCatalog (static, no daemon API needed).
// Shows all model families: LLMs, VLMs, TTS, image gen, video gen, music,
// 3D, embeddings, rerankers, sentiment, plus gated NSFW section.

#if os(macOS)
import SwiftUI
import SwooshGenerativeUI
import SwooshModels

public struct ModelsPane: View {
    @State private var searchText = ""
    @State private var selectedRuntime: RuntimeFilter = .all
    @State private var showNSFW = false

    public init() {}

    private var filteredModels: [UnifiedModelEntry] {
        let base = showNSFW ? UnifiedModelCatalog.allIncludingNSFW : UnifiedModelCatalog.all
        return base.filter { entry in
            let matchesRuntime: Bool = {
                switch selectedRuntime {
                case .all: return true
                case .cloud: return [.openAI, .openRouter, .codex, .router, .detourCloud].contains(entry.runtime)
                case .mlx: return entry.runtime == .localMLX
                case .ollama: return entry.runtime == .localOpenAI
                case .foundation: return entry.runtime == .localFoundation
                }
            }()
            let matchesSearch = searchText.isEmpty
                || entry.displayName.localizedCaseInsensitiveContains(searchText)
                || entry.family.localizedCaseInsensitiveContains(searchText)
                || entry.blurb.localizedCaseInsensitiveContains(searchText)
                || entry.modelID.localizedCaseInsensitiveContains(searchText)
            return matchesRuntime && matchesSearch
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statsRow
                filterBar
                searchBar
                categorizedList
            }
            .padding(24)
        }
        .background(SwooshNeonTokens.Canvas.bg)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Model Catalog")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(SwooshNeonTokens.Canvas.text1)
            Text("Local MLX, cloud providers, and specialized models")
                .font(.system(size: 12))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        let allModels = UnifiedModelCatalog.allIncludingNSFW
        let mlxCount = allModels.filter { $0.runtime == .localMLX }.count
        let cloudCount = allModels.filter { [.openAI, .openRouter, .codex, .router, .detourCloud].contains($0.runtime) }.count
        let nsfwCount = UnifiedModelCatalog.nsfwModels.count
        let generalCount = UnifiedModelCatalog.all.count

        return HStack(spacing: 12) {
            statCard("Total", value: "\(generalCount)", icon: "cpu", color: SwooshNeonTokens.Accent.cyan)
            statCard("MLX Local", value: "\(mlxCount)", icon: "memorychip", color: .green)
            statCard("Cloud", value: "\(cloudCount)", icon: "cloud", color: .blue)
            statCard("NSFW", value: "\(nsfwCount)", icon: "eye.slash", color: .red)
        }
    }

    private func statCard(_ label: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(color)
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
            }
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(color.opacity(0.12), lineWidth: 0.5)
        )
    }

    // MARK: - Filters

    private var filterBar: some View {
        HStack(spacing: 6) {
            ForEach(RuntimeFilter.allCases, id: \.self) { filter in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedRuntime = filter }
                } label: {
                    Text(filter.label)
                        .font(.system(size: 11, weight: selectedRuntime == filter ? .semibold : .regular))
                        .foregroundStyle(selectedRuntime == filter ? SwooshNeonTokens.Canvas.text1 : SwooshNeonTokens.Canvas.text3)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(selectedRuntime == filter
                                           ? SwooshNeonTokens.Accent.cyan.opacity(0.12)
                                           : Color.white.opacity(0.03))
                        )
                        .overlay(
                            Capsule().strokeBorder(selectedRuntime == filter
                                                   ? SwooshNeonTokens.Accent.cyan.opacity(0.3)
                                                   : SwooshNeonTokens.Line.rule, lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // NSFW toggle
            Toggle(isOn: $showNSFW) {
                HStack(spacing: 4) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 10))
                    Text("18+")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(showNSFW ? .red : SwooshNeonTokens.Canvas.text3)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            TextField("Search models…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(SwooshNeonTokens.Canvas.text1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(SwooshNeonTokens.Line.rule, lineWidth: 0.5)
        )
    }

    // MARK: - Categorized list

    private var categorizedList: some View {
        let models = filteredModels
        let categories = ModelCategory.allCases

        return ForEach(categories, id: \.self) { category in
            let categoryModels = models.filter { category.matches($0) }
            if !categoryModels.isEmpty {
                modelSection(category, models: categoryModels)
            }
        }
    }

    private func modelSection(_ category: ModelCategory, models: [UnifiedModelEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(category.color)
                Text(category.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                Text("(\(models.count))")
                    .font(.system(size: 11))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                Rectangle()
                    .fill(SwooshNeonTokens.Line.rule)
                    .frame(height: 0.5)
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                ForEach(models) { model in
                    modelCard(model)
                }
            }
        }
    }

    // MARK: - Model card

    private func modelCard(_ model: UnifiedModelEntry) -> some View {
        let isNSFW = model.contentRating == .nsfw
        let isAbliterated = model.displayName.contains("⛓️") || model.blurb.lowercased().contains("uncensored") || model.blurb.lowercased().contains("abliterated")

        return VStack(alignment: .leading, spacing: 8) {
            // Title row
            HStack(spacing: 6) {
                Text(model.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                    .lineLimit(1)
                Spacer()
                runtimeBadge(model.runtime)
            }

            // Family + badges
            HStack(spacing: 4) {
                Text(model.family)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(SwooshNeonTokens.Accent.cyan.opacity(0.1))
                    .clipShape(Capsule())

                if isNSFW {
                    Text("⚠️ NSFW")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Capsule())
                }

                if isAbliterated && !isNSFW {
                    Text("UNCENSORED")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                }

                if model.isLoRA {
                    Text("LoRA")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            // Blurb
            Text(model.blurb)
                .font(.system(size: 10))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                .lineLimit(2)

            // Bottom row: memory + capabilities
            HStack(spacing: 8) {
                if let mem = model.estimatedMemoryGB {
                    HStack(spacing: 3) {
                        Image(systemName: "memorychip")
                            .font(.system(size: 9))
                        Text(mem < 1 ? String(format: "%.0fMB", mem * 1024) : String(format: "%.1fGB", mem))
                            .font(.system(size: 9, design: .monospaced))
                    }
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                }

                if let ctx = model.contextWindow {
                    HStack(spacing: 3) {
                        Image(systemName: "text.justify.left")
                            .font(.system(size: 9))
                        Text(ctx >= 1_000_000 ? "\(ctx / 1_000_000)M" : "\(ctx / 1000)K")
                            .font(.system(size: 9, design: .monospaced))
                    }
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                }

                Spacer()

                // Capability dots
                HStack(spacing: 3) {
                    ForEach(Array(model.capabilities.sorted(by: { $0.rawValue < $1.rawValue }).prefix(5)), id: \.self) { cap in
                        capDot(cap)
                    }
                }
            }

            // Base model requirement for LoRAs
            if let baseModel = model.baseModelID {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 8))
                    Text("Requires: \(baseModel)")
                        .font(.system(size: 9, design: .monospaced))
                }
                .foregroundStyle(SwooshNeonTokens.Canvas.text3.opacity(0.7))
                .lineLimit(1)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isNSFW ? Color.red.opacity(0.3) : SwooshNeonTokens.Line.rule,
                    lineWidth: isNSFW ? 1 : 0.5
                )
        )
    }

    // MARK: - Visual elements

    @ViewBuilder
    private func runtimeBadge(_ runtime: ModelRuntimeKind) -> some View {
        let (label, color) = runtimeInfo(runtime)
        Text(label)
            .font(.system(size: 8, weight: .bold))
            .tracking(0.3)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func capDot(_ cap: ModelCapability) -> some View {
        Circle()
            .fill(capColor(cap))
            .frame(width: 6, height: 6)
            .help(cap.rawValue)
    }

    private func runtimeInfo(_ runtime: ModelRuntimeKind) -> (String, Color) {
        switch runtime {
        case .localMLX: return ("MLX", .green)
        case .localOpenAI: return ("OLLAMA", .orange)
        case .localLiteRT: return ("LITERT", .mint)
        case .localFoundation: return ("APPLE", .blue)
        case .openAI: return ("OPENAI", .cyan)
        case .openRouter: return ("OPENROUTER", .purple)
        case .codex: return ("CODEX", .cyan)
        case .router: return ("AUTO", .gray)
        case .detourCloud: return ("DETOUR", .pink)
        }
    }

    private func capColor(_ cap: ModelCapability) -> Color {
        switch cap {
        case .textGeneration, .summarization, .questionAnswering, .translation: return .cyan
        case .coding, .codeCompletion: return .green
        case .toolCalling: return .orange
        case .vision, .ocr, .objectDetection, .imageSegmentation, .depthEstimation, .imageClassification: return .purple
        case .embedding: return .yellow
        case .reranking: return .mint
        case .speechToText, .vad, .diarization, .audioSeparation: return .teal
        case .textToSpeech, .voiceCloning, .voiceDesign, .soundEffects: return .indigo
        case .imageGeneration, .imageEditing: return .pink
        case .videoGeneration: return Color(red: 1.0, green: 0.4, blue: 0.0)
        case .musicGeneration: return Color(red: 0.9, green: 0.2, blue: 0.5)
        case .threeD, .threeDReconstruction: return .brown
        case .sentimentAnalysis, .classification, .namedEntityRecognition: return .teal
        case .structuredOutput, .guard_, .judge: return .gray
        case .documentLayout: return .secondary
        @unknown default: return .gray
        }
    }
}

// MARK: - Filter types

private enum RuntimeFilter: CaseIterable {
    case all, cloud, mlx, ollama, foundation

    var label: String {
        switch self {
        case .all: return "All"
        case .cloud: return "Cloud"
        case .mlx: return "MLX"
        case .ollama: return "Ollama"
        case .foundation: return "Apple"
        }
    }
}

private enum ModelCategory: CaseIterable {
    case languageModels, visionVLM, tts, imageGen, videoGen, music, threeD, embeddings, rerankers, sentiment

    var title: String {
        switch self {
        case .languageModels: return "Language Models"
        case .visionVLM: return "Vision / VLM"
        case .tts: return "Text-to-Speech"
        case .imageGen: return "Image Generation"
        case .videoGen: return "Video Generation"
        case .music: return "Music Generation"
        case .threeD: return "3D Generation"
        case .embeddings: return "Embeddings"
        case .rerankers: return "Rerankers"
        case .sentiment: return "Sentiment / Classification"
        }
    }

    var icon: String {
        switch self {
        case .languageModels: return "text.bubble"
        case .visionVLM: return "eye"
        case .tts: return "speaker.wave.3"
        case .imageGen: return "photo"
        case .videoGen: return "film"
        case .music: return "music.note"
        case .threeD: return "cube"
        case .embeddings: return "arrow.triangle.branch"
        case .rerankers: return "arrow.up.arrow.down"
        case .sentiment: return "face.smiling"
        }
    }

    var color: Color {
        switch self {
        case .languageModels: return .cyan
        case .visionVLM: return .purple
        case .tts: return .indigo
        case .imageGen: return .pink
        case .videoGen: return .orange
        case .music: return Color(red: 0.9, green: 0.2, blue: 0.5)
        case .threeD: return .brown
        case .embeddings: return .yellow
        case .rerankers: return .mint
        case .sentiment: return .teal
        }
    }

    func matches(_ model: UnifiedModelEntry) -> Bool {
        switch self {
        case .languageModels:
            return model.capabilities.contains(.textGeneration)
                && !model.capabilities.contains(.vision)
                && !model.capabilities.contains(.textToSpeech)
                && !model.capabilities.contains(.imageGeneration)
                && !model.capabilities.contains(.videoGeneration)
                && !model.capabilities.contains(.embedding)
                && !model.capabilities.contains(.reranking)
                && !model.capabilities.contains(.sentimentAnalysis)
                && !model.capabilities.contains(.musicGeneration)
                && !model.capabilities.contains(.threeD)
        case .visionVLM:
            return model.capabilities.contains(.vision) && model.capabilities.contains(.textGeneration)
        case .tts:
            return model.capabilities.contains(.textToSpeech)
        case .imageGen:
            return model.capabilities.contains(.imageGeneration) && !model.capabilities.contains(.videoGeneration)
        case .videoGen:
            return model.capabilities.contains(.videoGeneration)
        case .music:
            return model.capabilities.contains(.musicGeneration)
        case .threeD:
            return model.capabilities.contains(.threeD)
        case .embeddings:
            return model.capabilities.contains(.embedding)
        case .rerankers:
            return model.capabilities.contains(.reranking)
        case .sentiment:
            return model.capabilities.contains(.sentimentAnalysis) || model.capabilities.contains(.classification)
        }
    }
}

#endif
