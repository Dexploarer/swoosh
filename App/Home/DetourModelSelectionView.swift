// DetourModelSelectionView.swift — model provider picker for Detour home (0.5A)

import SwiftUI

struct DetourModelSelectionView: View {
    let providers: [ProviderSummary]
    let selectedProviderID: String
    let selectedModelID: String
    let busyModelID: String?
    let status: String
    let hasSignal: (String) -> Bool
    let select: (DetourModelOption) -> Void
    let refresh: () -> Void

    private let options = DetourModelOption.catalog
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            topBar
            providerStrip
            TextField("Search models", text: $search)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.white.opacity(0.08), in: Capsule())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                ForEach(filteredOptions) { option in
                    modelCard(option)
                }
            }
        }
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Models")
                    .font(.title3.weight(.semibold))
                Text(status.isEmpty ? currentLabel : status)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Refresh", action: refresh)
                .buttonStyle(.bordered)
        }
    }

    private var providerStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(providerOptions) { provider in
                    Button {
                        select(provider.defaultModel)
                    } label: {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(providerColor(provider.id))
                                .frame(width: 7, height: 7)
                            Text(provider.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(provider.id == selectedProviderID ? .white.opacity(0.18) : .white.opacity(0.07), in: Capsule())
                }
            }
        }
    }

    private func modelCard(_ option: DetourModelOption) -> some View {
        Button {
            select(option)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Image(systemName: option.systemImage)
                        .font(.headline)
                    Spacer()
                    Text(option.badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(option.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(option.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack {
                    Text(buttonLabel(option))
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Circle()
                        .fill(isSelected(option) ? .green : providerColor(option.providerID))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .background(.white.opacity(isSelected(option) ? 0.12 : 0.055), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected(option) ? .green.opacity(0.36) : .white.opacity(0.10), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(busyModelID == option.id)
    }

    private var filteredOptions: [DetourModelOption] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return options }
        return options.filter {
            [$0.title, $0.subtitle, $0.providerName, $0.modelID]
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var providerOptions: [DetourModelProviderOption] {
        var seen = Set<String>()
        return options.compactMap { option in
            guard seen.insert(option.providerID).inserted else { return nil }
            return DetourModelProviderOption(
                id: option.providerID,
                title: option.providerName,
                defaultModel: option
            )
        }
    }

    private var currentLabel: String {
        guard let current = options.first(where: { isSelected($0) }) else { return "Choose a model." }
        return "\(current.providerName) · \(current.title)"
    }

    private func buttonLabel(_ option: DetourModelOption) -> String {
        if busyModelID == option.id { return "Saving" }
        return isSelected(option) ? "Selected" : "Use"
    }

    private func isSelected(_ option: DetourModelOption) -> Bool {
        option.providerID == selectedProviderID && option.modelID == selectedModelID
    }

    private func providerColor(_ providerID: String) -> Color {
        if providerID == ModelDefaults.routerProviderID { return .green }
        if providerID == selectedProviderID { return .green }
        if let provider = providers.first(where: { $0.id == providerID }) {
            return provider.configured ? .green : .orange
        }
        return hasSignal(providerID) ? .green : .white.opacity(0.46)
    }
}

private struct DetourModelProviderOption: Identifiable {
    let id: String
    let title: String
    let defaultModel: DetourModelOption
}

struct DetourModelOption: Identifiable, Equatable {
    let id: String
    let providerID: String
    let providerName: String
    let modelID: String
    let title: String
    let subtitle: String
    let badge: String
    let systemImage: String

    static let catalog: [DetourModelOption] = {
        UnifiedModelCatalog.all
            .filter(isSelectable)
            .sorted(by: sort)
            .map(option)
    }()

    static func defaultOption(providerID: String?, modelID: String?) -> DetourModelOption {
        let provider = providerID ?? ModelDefaults.routerProviderID
        let model = modelID ?? UnifiedModelCatalog.defaultModel(providerID: provider) ?? ModelDefaults.routerModelID
        return catalog.first { $0.providerID == provider && $0.modelID == model }
            ?? catalog.first { $0.providerID == provider }
            ?? catalog[0]
    }

    private static func option(_ entry: UnifiedModelEntry) -> DetourModelOption {
        DetourModelOption(
            id: "\(entry.providerID):\(entry.modelID)",
            providerID: entry.providerID,
            providerName: UnifiedModelCatalog.providerDisplayName(entry.providerID),
            modelID: entry.modelID,
            title: entry.displayName,
            subtitle: subtitle(entry),
            badge: badge(entry),
            systemImage: systemImage(entry)
        )
    }

    private static func isSelectable(_ entry: UnifiedModelEntry) -> Bool {
        entry.capabilities.contains(.textGeneration)
            && !entry.capabilities.contains(.embedding)
            && !entry.capabilities.contains(.speechToText)
            && !entry.capabilities.contains(.textToSpeech)
            && !entry.capabilities.contains(.imageGeneration)
            && !entry.capabilities.contains(.reranking)
    }

    private static func subtitle(_ entry: UnifiedModelEntry) -> String {
        if let memory = entry.estimatedMemoryGB {
            return "\(entry.family) · \(memory.formatted(.number.precision(.fractionLength(0...1)))) GB"
        }
        if let window = entry.contextWindow, window > 0 {
            return "\(entry.family) · \(window / 1000)K"
        }
        return entry.family
    }

    private static func badge(_ entry: UnifiedModelEntry) -> String {
        switch entry.runtime {
        case .router: "Auto"
        case .codex: "Codex"
        case .openAI, .openRouter, .elizaCloud: "Cloud"
        case .localOpenAI, .localMLX, .localLiteRT, .localFoundation: "Local"
        }
    }

    private static func systemImage(_ entry: UnifiedModelEntry) -> String {
        switch entry.runtime {
        case .router: "arrow.triangle.branch"
        case .codex: "sparkles"
        case .openAI, .openRouter, .elizaCloud: "cloud"
        case .localOpenAI: "desktopcomputer"
        case .localMLX, .localLiteRT: "cpu"
        case .localFoundation: "apple.logo"
        }
    }

    private static func sort(_ lhs: UnifiedModelEntry, _ rhs: UnifiedModelEntry) -> Bool {
        let left = "\(order(lhs.providerID))|\(lhs.family)|\(lhs.displayName)"
        let right = "\(order(rhs.providerID))|\(rhs.family)|\(rhs.displayName)"
        return left < right
    }

    private static func order(_ providerID: String) -> Int {
        switch providerID {
        case ModelDefaults.routerProviderID: 0
        case ModelDefaults.codexProviderID: 1
        case ModelDefaults.openAIProviderID: 2
        case ModelDefaults.openRouterProviderID: 3
        case ModelDefaults.elizaCloudProviderID: 4
        case ModelDefaults.localMLXProviderID: 5
        case ModelDefaults.localOpenAIProviderID: 6
        case ModelDefaults.localFoundationProviderID: 7
        default: 20
        }
    }
}
