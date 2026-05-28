// SwooshUI/Pickers/DatasetBrowserView.swift — HuggingFace dataset browser — 0.9T
//
// Premium glassmorphic sheet for searching, filtering, and previewing
// HuggingFace datasets. Task-category chip bar, neon card rows with
// animated expand/collapse, size-tier color coding, and paginated results.

import SwiftUI
import SwooshGenerativeUI
import SwooshModels

// ═══════════════════════════════════════════════════════════════════
// MARK: - Public entry point
// ═══════════════════════════════════════════════════════════════════

public struct DatasetBrowserView: View {

    // MARK: - State

    @State private var searchQuery = ""
    @State private var committedQuery = ""
    @State private var selectedTask: String?
    @State private var datasets: [HFDatasetEntry] = []
    @State private var isLoading = false
    @State private var expandedID: String?
    @State private var currentPage = 0
    @State private var hasMore = true

    @Environment(\.dismiss) private var dismiss

    private let discovery = HuggingFaceDiscovery()
    private let pageSize = 20

    /// Callback when the user taps "Download" on a dataset row.
    public var onDownload: ((HFDatasetEntry) -> Void)?

    public init(onDownload: ((HFDatasetEntry) -> Void)? = nil) {
        self.onDownload = onDownload
    }

    // MARK: - Task categories

    private static let taskCategories: [(label: String, value: String)] = [
        ("Text Classification",   "text-classification"),
        ("Question Answering",    "question-answering"),
        ("Text Generation",       "text-generation"),
        ("Translation",           "translation"),
        ("Summarization",         "summarization"),
        ("Token Classification",  "token-classification"),
        ("Fill Mask",             "fill-mask"),
    ]

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            chipBar
            divider
            content
        }
        .frame(width: 680, height: 600)
        .background(SwooshNeonTokens.Canvas.bg)
        .task(id: committedQuery + (selectedTask ?? "")) {
            // Debounce: reset and fetch
            currentPage = 0
            hasMore = true
            await fetchDatasets(reset: true)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "text.book.closed")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                Text("DATASETS")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(SwooshNeonTokens.Accent.cyan)
            }
            Spacer()
            Button { dismiss() } label: {
                Text("Done")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SwooshNeonTokens.Accent.cyan)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)

            TextField("Search HuggingFace Datasets…", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                .onSubmit {
                    committedQuery = searchQuery
                }

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    committedQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Category chip bar

    private var chipBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // "All" chip
                chipButton(label: "All", isActive: selectedTask == nil) {
                    withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                        selectedTask = nil
                    }
                }

                ForEach(Self.taskCategories, id: \.value) { category in
                    chipButton(label: category.label, isActive: selectedTask == category.value) {
                        withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                            selectedTask = selectedTask == category.value ? nil : category.value
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func chipButton(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isActive ? .white : SwooshNeonTokens.Canvas.text2)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    if isActive {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        SwooshNeonTokens.Accent.cyan,
                                        SwooshNeonTokens.Accent.cyan.opacity(0.7)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    } else {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                            )
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(SwooshNeonTokens.Line.rule)
            .frame(height: 0.5)
    }

    // MARK: - Content area

    @ViewBuilder
    private var content: some View {
        if isLoading && datasets.isEmpty {
            loadingState
        } else if datasets.isEmpty && !committedQuery.isEmpty {
            emptySearchState
        } else if datasets.isEmpty {
            initialState
        } else {
            resultsList
        }
    }

    // MARK: - Empty states

    private var initialState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "text.book.closed.fill")
                .font(.system(size: 44))
                .foregroundStyle(
                    LinearGradient(
                        colors: [SwooshNeonTokens.Accent.cyan, SwooshNeonTokens.Accent.cyan.opacity(0.4)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: SwooshNeonTokens.Accent.cyan.opacity(0.3), radius: 12)

            Text("Search HuggingFace Datasets")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(SwooshNeonTokens.Canvas.text1)

            Text("Find training data, benchmarks, and evaluation sets\nfrom the HuggingFace Hub.")
                .font(.system(size: 12))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptySearchState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)

            Text("No datasets found")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(SwooshNeonTokens.Canvas.text1)

            Text("Try a different search term or remove the task filter.")
                .font(.system(size: 12))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(SwooshNeonTokens.Accent.cyan)

            Text("Searching datasets…")
                .font(.system(size: 13))
                .foregroundStyle(SwooshNeonTokens.Canvas.text2)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results list

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(datasets) { dataset in
                    datasetRow(dataset)
                }

                if hasMore {
                    loadMoreButton
                }
            }
            .padding(16)
        }
    }

    // MARK: - Dataset row

    @ViewBuilder
    private func datasetRow(_ dataset: HFDatasetEntry) -> some View {
        let isExpanded = expandedID == dataset.id

        VStack(alignment: .leading, spacing: 0) {
            // Main row
            Button {
                withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                    expandedID = isExpanded ? nil : dataset.id
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(dataset.displayName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                                .lineLimit(1)

                            Text(dataset.author)
                                .font(.system(size: 11))
                                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                                .lineLimit(1)
                        }

                        // Stats row
                        HStack(spacing: 12) {
                            statBadge(icon: "arrow.down.circle", value: formatCount(dataset.downloads))
                            statBadge(icon: "heart", value: formatCount(dataset.likes))
                        }
                    }

                    Spacer()

                    // Size badge
                    sizeBadge(dataset.formattedSize, bytes: dataset.sizeBytes)

                    // Expand chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            // Tags
            if !dataset.tags.prefix(5).isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(dataset.tags.prefix(5)), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.05))
                                )
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 8)
            }

            // Expanded details
            if isExpanded {
                expandedDetails(dataset)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .neonTile(.cyan, state: isExpanded ? .focus : .idle, shape: .card)
        .contentShape(RoundedRectangle(cornerRadius: SwooshNeonTokens.Radius.card, style: .continuous))
    }

    // MARK: - Row components

    @ViewBuilder
    private func statBadge(icon: String, value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(value)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
    }

    @ViewBuilder
    private func sizeBadge(_ label: String, bytes: Int64?) -> some View {
        let color = sizeColor(bytes: bytes)
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.12))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(color.opacity(0.3), lineWidth: 0.5)
                    )
            )
    }

    private func sizeColor(bytes: Int64?) -> Color {
        guard let bytes else { return SwooshNeonTokens.Canvas.text3 }
        let gb = Double(bytes) / 1_073_741_824
        if gb > 10 { return .red }
        if gb >= 1 { return .orange }
        return SwooshNeonTokens.Accent.green
    }

    // MARK: - Expanded details

    @ViewBuilder
    private func expandedDetails(_ dataset: HFDatasetEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle()
                .fill(SwooshNeonTokens.Line.rule)
                .frame(height: 0.5)
                .padding(.horizontal, 12)

            if let description = dataset.description, !description.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DESCRIPTION")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                        .lineLimit(4)
                }
                .padding(.horizontal, 12)
            }

            if let license = dataset.license {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 9))
                    Text("License: \(license)")
                        .font(.system(size: 10))
                }
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                .padding(.horizontal, 12)
            }

            if !dataset.taskCategories.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "tag")
                        .font(.system(size: 9))
                    Text("Tasks: \(dataset.taskCategories.joined(separator: ", "))")
                        .font(.system(size: 10))
                        .lineLimit(1)
                }
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                .padding(.horizontal, 12)
            }

            if let citation = dataset.citation, !citation.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CITATION")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                    Text(citation)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                        .lineLimit(3)
                }
                .padding(.horizontal, 12)
            }

            // Download button
            HStack {
                Spacer()
                Button {
                    onDownload?(dataset)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Download")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(SwooshNeonTokens.Accent.cyan.opacity(0.5), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .neonGlow(.cyan, intensity: SwooshNeonTokens.Glow.idle)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Load More

    private var loadMoreButton: some View {
        Button {
            Task { await fetchDatasets(reset: false) }
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(SwooshNeonTokens.Accent.cyan)
                }
                Text(isLoading ? "Loading…" : "Load More")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SwooshNeonTokens.Accent.cyan)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .overlay(
                RoundedRectangle(cornerRadius: SwooshNeonTokens.Radius.card, style: .continuous)
                    .strokeBorder(
                        SwooshNeonTokens.Accent.cyan.opacity(SwooshNeonTokens.Line.dim),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    // MARK: - Data fetching

    private func fetchDatasets(reset: Bool) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let results = try await discovery.discoverDatasets(
                query: committedQuery,
                task: selectedTask,
                limit: pageSize
            )

            if reset {
                withAnimation(.easeInOut(duration: 0.25)) {
                    datasets = results
                }
            } else {
                // Deduplicate on append
                let existingIDs = Set(datasets.map(\.id))
                let newItems = results.filter { !existingIDs.contains($0.id) }
                withAnimation(.easeInOut(duration: 0.25)) {
                    datasets.append(contentsOf: newItems)
                }
            }

            hasMore = results.count >= pageSize
            if !reset { currentPage += 1 }
        } catch {
            // Silently handle errors — the empty state will show
            if reset {
                withAnimation { datasets = [] }
            }
            hasMore = false
        }
    }

    // MARK: - Formatting

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
        if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Preview
// ═══════════════════════════════════════════════════════════════════

#if DEBUG
#Preview("Dataset Browser") {
    DatasetBrowserView()
        .preferredColorScheme(.dark)
}
#endif
