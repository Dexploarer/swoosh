// SwooshUI/Pickers/ModelPicker.swift — 0.9R Model + Reasoning picker (neon)
//
// Trigger reads "<model-short> <effort> ⌄" with a hairline-cyan outline and
// subtle glow at rest. Opens a Menu with two axes:
//   • Model: 2 featured + "Other models" submenu drawn from CloudCatalog
//   • Intelligence: Low / Medium / High / Extra High (only when the model
//     declares `supportsReasoningEffort = true`)
//
// Selected row gets a cyan dot prefix; the glow on the trigger reads as
// "this is the current model" without a checkmark. API surface unchanged.

import SwiftUI
import SwooshGenerativeUI
import SwooshModels
import SwooshProviders

public struct ModelPicker: View {

    // MARK: - Inputs

    public let models: [CloudModelEntry]
    @Binding public var selectedModelID: String
    @Binding public var effort: ReasoningEffort
    public let featuredCount: Int

    /// Domain accent. Default `.cyan` matches the neutral picker shown in
    /// the Configurations sheet; a wallet-side picker can adopt `.green`.
    public let accent: NeonAccent

    public init(
        models: [CloudModelEntry],
        selectedModelID: Binding<String>,
        effort: Binding<ReasoningEffort>,
        featuredCount: Int = 2,
        accent: NeonAccent = .cyan
    ) {
        self.models = models
        self._selectedModelID = selectedModelID
        self._effort = effort
        self.featuredCount = featuredCount
        self.accent = accent
    }

    // MARK: - Body

    public var body: some View {
        Menu {
            modelSection
            if currentSupportsEffort {
                Divider()
                effortSection
            }
        } label: {
            triggerLabel
        }
        .menuStyle(.borderlessButton)
        .help("Switch model or reasoning depth")
    }

    // MARK: - Trigger

    private var triggerLabel: some View {
        HStack(spacing: SwooshNeonTokens.Spacing.micro) {
            Text(shortLabel(currentModel?.displayName ?? selectedModelID))
                .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                .fontWeight(.medium)
            if currentSupportsEffort {
                Text(effort.displayName.lowercased())
                    .foregroundStyle(SwooshNeonTokens.Canvas.text2)
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SwooshNeonTokens.Canvas.text2)
        }
        .padding(.horizontal, SwooshNeonTokens.Spacing.base + 2)
        .padding(.vertical, SwooshNeonTokens.Spacing.micro)
        .neonTile(accent, state: .idle, shape: .card)
        .contentShape(RoundedRectangle(cornerRadius: SwooshNeonTokens.Radius.card, style: .continuous))
    }

    // MARK: - Menu sections

    @ViewBuilder
    private var modelSection: some View {
        Section("Model") {
            ForEach(featured) { entry in
                modelRow(entry)
            }
            if !overflow.isEmpty {
                Menu("Other models") {
                    ForEach(overflow) { entry in
                        modelRow(entry)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func modelRow(_ entry: CloudModelEntry) -> some View {
        Button {
            selectedModelID = entry.id
        } label: {
            // Native menu items can't host arbitrary styled views in
            // SwiftUI; a leading bullet glyph + name communicates the
            // selection without a checkmark.
            Text(entry.id == selectedModelID
                 ? "• \(entry.displayName)"
                 : "  \(entry.displayName)")
        }
    }

    @ViewBuilder
    private var effortSection: some View {
        Section("Intelligence") {
            ForEach(ReasoningEffort.allCases, id: \.self) { level in
                Button {
                    effort = level
                } label: {
                    Text(level == effort
                         ? "• \(level.displayName)"
                         : "  \(level.displayName)")
                }
            }
        }
    }

    // MARK: - Derived

    private var currentModel: CloudModelEntry? {
        models.first(where: { $0.id == selectedModelID })
    }

    private var currentSupportsEffort: Bool {
        currentModel?.supportsReasoningEffort ?? false
    }

    private var featured: [CloudModelEntry] {
        Array(models.prefix(featuredCount))
    }

    private var overflow: [CloudModelEntry] {
        Array(models.dropFirst(featuredCount))
    }

    /// "GPT-5.5" -> "5.5". Compact trigger glyph matching the Codex picker.
    private func shortLabel(_ name: String) -> String {
        if let dash = name.firstIndex(of: "-") {
            return String(name[name.index(after: dash)...])
        }
        return name
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Neon · cyan") {
    StatefulPreview()
        .padding(40)
        .frame(width: 320)
        .background(VoltPaper.background)
}

private struct StatefulPreview: View {
    @State private var model: String = ModelDefaults.openAIModelID
    @State private var effort: ReasoningEffort = .extraHigh

    var body: some View {
        ModelPicker(
            models: CloudCatalog.all,
            selectedModelID: $model,
            effort: $effort
        )
    }
}
#endif
