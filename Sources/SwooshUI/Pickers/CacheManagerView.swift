// SwooshUI/Pickers/CacheManagerView.swift — Model cache dashboard + purge controls — 0.9T
//
// Glassmorphic sheet showing a donut chart of disk usage, per-source cache
// bars, a scrollable model list with size badges and delete controls, and
// bulk purge actions. Presentable as a `.sheet` from MemoryBudgetView or
// any settings surface.

import SwiftUI
import SwooshModels
import SwooshGenerativeUI

// ═══════════════════════════════════════════════════════════════════
// MARK: - CacheManagerView
// ═══════════════════════════════════════════════════════════════════

public struct CacheManagerView: View {

    @State private var cacheManager = CacheManager()
    @State private var snapshot: CacheSnapshot?
    @State private var isLoading = true
    @State private var error: String?

    // Purge confirmation
    @State private var showPurgeAllConfirm = false
    @State private var showPurgeSourceConfirm = false
    @State private var purgeSource: CacheSource?

    // Delete single entry
    @State private var entryToDelete: CacheEntry?
    @State private var showDeleteConfirm = false

    // Freed-space animation
    @State private var freedGB: Double = 0
    @State private var showFreed = false

    // Chart animation
    @State private var chartAppeared = false

    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(SwooshNeonTokens.Line.rule).frame(height: 0.5)

            if isLoading {
                loadingView
            } else if let snapshot, !snapshot.entries.isEmpty {
                ScrollView {
                    VStack(spacing: 20) {
                        diskDonut(snapshot: snapshot)
                        cacheBreakdown(snapshot: snapshot)
                        modelList(snapshot: snapshot)
                        actionButtons
                    }
                    .padding(20)
                }
            } else {
                emptyState
            }
        }
        .frame(width: 520, height: 640)
        .background(SwooshNeonTokens.Canvas.bg)
        .task { await performScan() }
        .alert("Clear All Model Caches?", isPresented: $showPurgeAllConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) { Task { await purgeAll() } }
        } message: {
            Text("This will remove all cached models from Ollama, HuggingFace, MLX, and Swoosh directories. You can re-download them later.")
        }
        .alert("Clear \(purgeSource?.displayName ?? "") Cache?", isPresented: $showPurgeSourceConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { Task { await purgeBySource() } }
        } message: {
            if let src = purgeSource, let snap = snapshot {
                Text("Remove \(String(format: "%.1f", snap.sizeGB(for: src))) GB of \(src.displayName) model cache.")
            }
        }
        .alert("Delete \(entryToDelete?.name ?? "")?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await deleteEntry() } }
        } message: {
            if let entry = entryToDelete {
                Text("Remove \(String(format: "%.2f", entry.sizeGB)) GB from disk.")
            }
        }
        .overlay {
            if showFreed {
                freedBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "internaldrive")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SwooshNeonTokens.Accent.cyan)
            Text("MODEL CACHE")
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(SwooshNeonTokens.Accent.cyan)
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

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
                .tint(SwooshNeonTokens.Accent.cyan)
            Text("Scanning model caches…")
                .font(.system(size: 13))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            Spacer()
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(SwooshNeonTokens.Accent.green)
                .symbolEffect(.pulse, options: .repeating)
            Text("No cached models")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SwooshNeonTokens.Canvas.text1)
            Text("Your disk is clean — no model caches found.")
                .font(.system(size: 13))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            Spacer()
        }
    }

    // MARK: - Donut chart

    @ViewBuilder
    private func diskDonut(snapshot: CacheSnapshot) -> some View {
        let disk = snapshot.disk
        let modelGB = snapshot.totalCacheGB
        let otherUsedGB = max(disk.usedGB - modelGB, 0)
        let freeGB = disk.freeGB
        let total = disk.totalGB

        // Proportions
        let modelFrac = total > 0 ? modelGB / total : 0
        let usedFrac  = total > 0 ? otherUsedGB / total : 0
        let freeFrac  = total > 0 ? freeGB / total : 0

        VStack(spacing: 12) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 20)

                // Used (non-model) arc
                Circle()
                    .trim(from: 0, to: chartAppeared ? usedFrac : 0)
                    .stroke(Color.white.opacity(0.20), style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                // Model arc
                Circle()
                    .trim(from: 0, to: chartAppeared ? modelFrac : 0)
                    .stroke(
                        LinearGradient(
                            colors: [SwooshNeonTokens.Accent.cyan, SwooshNeonTokens.Accent.cyan.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90 + 360 * usedFrac))
                    .shadow(color: SwooshNeonTokens.Accent.cyan.opacity(0.3), radius: 6)

                // Free arc
                Circle()
                    .trim(from: 0, to: chartAppeared ? freeFrac : 0)
                    .stroke(SwooshNeonTokens.Accent.green.opacity(0.3), style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    .rotationEffect(.degrees(-90 + 360 * (usedFrac + modelFrac)))

                // Center label
                VStack(spacing: 2) {
                    Text(String(format: "%.1f", modelGB))
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                    Text("GB Models")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                }
            }
            .frame(width: 140, height: 140)
            .animation(.easeInOut(duration: 0.8), value: chartAppeared)
            .onAppear { chartAppeared = true }

            // Legend row
            HStack(spacing: 16) {
                legendDot(color: Color.white.opacity(0.20), label: "System: \(String(format: "%.0f", otherUsedGB)) GB")
                legendDot(color: SwooshNeonTokens.Accent.cyan, label: "Models: \(String(format: "%.1f", modelGB)) GB")
                legendDot(color: SwooshNeonTokens.Accent.green.opacity(0.3), label: "Free: \(String(format: "%.0f", freeGB)) GB")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(SwooshNeonTokens.Accent.cyan.opacity(0.12), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Cache breakdown bars

    @ViewBuilder
    private func cacheBreakdown(snapshot: CacheSnapshot) -> some View {
        let maxBytes = CacheSource.allCases.map { snapshot.bytes(for: $0) }.max() ?? 1

        VStack(alignment: .leading, spacing: 10) {
            Text("CACHE BY SOURCE")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)

            ForEach(CacheSource.allCases) { source in
                let bytes = snapshot.bytes(for: source)
                let gb = snapshot.sizeGB(for: source)
                let ratio = maxBytes > 0 ? Double(bytes) / Double(maxBytes) : 0

                HStack(spacing: 10) {
                    Text(source.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                        .frame(width: 80, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [sourceColor(source), sourceColor(source).opacity(0.5)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(geo.size.width * (chartAppeared ? ratio : 0), bytes > 0 ? 4 : 0))
                                .animation(.easeInOut(duration: 0.6).delay(0.1), value: chartAppeared)
                        }
                    }
                    .frame(height: 8)

                    Text(bytes > 0 ? String(format: "%.1f GB", gb) : "—")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(bytes > 0 ? SwooshNeonTokens.Canvas.text2 : SwooshNeonTokens.Canvas.text3)
                        .frame(width: 54, alignment: .trailing)
                }
                .frame(height: 16)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Model list

    @ViewBuilder
    private func modelList(snapshot: CacheSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CACHED MODELS")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                Spacer()
                Text("\(snapshot.entries.count) items")
                    .font(.system(size: 9))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            }

            ForEach(snapshot.entries) { entry in
                modelRow(entry: entry)
            }
        }
    }

    @ViewBuilder
    private func modelRow(entry: CacheEntry) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                    .lineLimit(1)

                HStack(spacing: 0) {
                    Text(entry.lastAccessed, style: .relative)
                    Text(" ago")
                }
                .font(.system(size: 9))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            }

            Spacer()

            // Source pill
            Text(entry.source.badge)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(sourceColor(entry.source))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(sourceColor(entry.source).opacity(0.12))
                )

            // Size badge
            Text(String(format: "%.1f GB", entry.sizeGB))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(sizeBadgeColor(entry.sizeGB))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(sizeBadgeColor(entry.sizeGB).opacity(0.10))
                )

            // Delete button
            Button {
                entryToDelete = entry
                showDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.7))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete \(entry.name)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            // Clear All
            Button {
                showPurgeAllConfirm = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 11))
                    Text("Clear All Caches")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.red.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(.red.opacity(0.20), lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)

            // Per-source buttons
            HStack(spacing: 8) {
                ForEach(CacheSource.allCases) { source in
                    let hasData = snapshot.map { $0.bytes(for: source) > 0 } ?? false
                    Button {
                        purgeSource = source
                        showPurgeSourceConfirm = true
                    } label: {
                        Text(source.badge)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(hasData ? sourceColor(source) : SwooshNeonTokens.Canvas.text3)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(sourceColor(source).opacity(hasData ? 0.06 : 0.02))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(sourceColor(source).opacity(hasData ? 0.15 : 0.05), lineWidth: 0.5)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasData)
                }
            }
        }
    }

    // MARK: - Freed banner

    private var freedBanner: some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(SwooshNeonTokens.Accent.green)
                    .symbolEffect(.bounce, value: showFreed)
                Text(String(format: "%.2f GB freed", freedGB))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(SwooshNeonTokens.Accent.green)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(SwooshNeonTokens.Accent.green.opacity(0.3), lineWidth: 0.5)
                    )
            )
            .shadow(color: SwooshNeonTokens.Accent.green.opacity(0.2), radius: 12)
            .padding(.top, 60)
            Spacer()
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
        }
    }

    private func sourceColor(_ source: CacheSource) -> Color {
        switch source {
        case .ollama:      return .purple
        case .huggingface: return SwooshNeonTokens.Accent.gold
        case .mlx:         return SwooshNeonTokens.Accent.cyan
        case .swoosh:      return SwooshNeonTokens.Accent.green
        }
    }

    /// Color-code size badges: green < 2 GB, orange 2-8 GB, red > 8 GB.
    private func sizeBadgeColor(_ gb: Double) -> Color {
        if gb > 8  { return .red }
        if gb > 2  { return .orange }
        return SwooshNeonTokens.Accent.green
    }

    // MARK: - Actions

    private func performScan() async {
        isLoading = true
        error = nil
        do {
            let result = try await cacheManager.scan()
            withAnimation(.easeInOut(duration: 0.3)) {
                snapshot = result
                isLoading = false
            }
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    private func purgeAll() async {
        do {
            let freed = try await cacheManager.purgeAll()
            showFreedBanner(freed)
            await performScan()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func purgeBySource() async {
        guard let source = purgeSource else { return }
        do {
            let freed = try await cacheManager.purgeSource(source)
            showFreedBanner(freed)
            await performScan()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteEntry() async {
        guard let entry = entryToDelete else { return }
        do {
            let freed = try await cacheManager.purge(entries: [entry])
            showFreedBanner(freed)
            await performScan()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func showFreedBanner(_ gb: Double) {
        freedGB = gb
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            showFreed = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.easeOut(duration: 0.3)) {
                showFreed = false
            }
        }
    }
}
