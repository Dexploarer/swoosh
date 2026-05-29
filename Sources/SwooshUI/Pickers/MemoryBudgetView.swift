// SwooshUI/Pickers/MemoryBudgetView.swift — Hardware banner + memory budget bar
//
// Shows the user's chip, total RAM, and a live memory budget bar that updates
// as the user selects different local model combinations. Color-coded:
//   green (< 60%), yellow (60-85%), red (> 85%)

import SwiftUI
import SwooshModels
import SwooshGenerativeUI

// ═══════════════════════════════════════════════════════════════════
// MARK: - Hardware banner
// ═══════════════════════════════════════════════════════════════════

public struct MemoryBudgetView: View {

    let hardware: HardwareProfile
    let selectedModels: [UnifiedModelEntry]

    @State private var diskFreeGB: Double = 0
    @State private var diskTotalGB: Double = 0
    @State private var cachedModelsGB: Double = 0
    @State private var showCacheManager = false

    public init(hardware: HardwareProfile, selectedModels: [UnifiedModelEntry]) {
        self.hardware = hardware
        self.selectedModels = selectedModels
    }

    private var totalModelMemory: Double {
        selectedModels.compactMap(\.estimatedMemoryGB).reduce(0, +)
    }

    private var osOverhead: Double { 4.0 }

    private var totalUsed: Double {
        osOverhead + totalModelMemory
    }

    private var usageRatio: Double {
        min(totalUsed / hardware.totalMemoryGB, 1.0)
    }

    private var barColor: Color {
        if usageRatio > 0.85 { return VoltPaper.destructive }
        if usageRatio > 0.60 { return VoltPaper.Chart.c4 }
        return SwooshNeonTokens.Accent.cyan
    }

    private var available: Double {
        max(hardware.totalMemoryGB - totalUsed, 0)
    }

    public var body: some View {
        VStack(spacing: 10) {
            // ── Chip + RAM header ──
            HStack(spacing: 8) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 14))
                    .foregroundStyle(SwooshNeonTokens.Accent.cyan)

                VStack(alignment: .leading, spacing: 1) {
                    Text(hardware.chip)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                    Text("\(Int(hardware.totalMemoryGB)) GB Unified Memory")
                        .font(.system(size: 11))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                }

                Spacer()

                // Total usage badge
                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: "%.1f / %.0f GB", totalUsed, hardware.totalMemoryGB))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(barColor)
                    Text(usageRatio > 0.85 ? "⚠ Over budget" : "\(String(format: "%.1f", available)) GB free")
                        .font(.system(size: 10))
                        .foregroundStyle(usageRatio > 0.85 ? VoltPaper.destructive.opacity(0.8) : SwooshNeonTokens.Canvas.text3)
                }
            }

            // ── Memory bar ──
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(VoltPaper.foreground.opacity(0.06))

                    // OS overhead segment
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(VoltPaper.foreground.opacity(0.12))
                        .frame(width: max(geo.size.width * (osOverhead / hardware.totalMemoryGB), 0))

                    // Total fill
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [barColor.opacity(0.8), barColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * usageRatio, 0))
                        .animation(.easeInOut(duration: 0.3), value: totalModelMemory)
                }
            }
            .frame(height: 8)

            // ── Legend ──
            HStack(spacing: 16) {
                legendDot(color: VoltPaper.foreground.opacity(0.12), label: "OS + Apps: \(String(format: "%.1f", osOverhead)) GB")
                legendDot(color: barColor, label: "Models: \(String(format: "%.1f", totalModelMemory)) GB")
                Spacer()
                legendDot(color: VoltPaper.foreground.opacity(0.06), label: "Available: \(String(format: "%.1f", available)) GB")
            }

            // ── Disk storage row ──
            if diskTotalGB > 0 {
                Divider()
                    .overlay(VoltPaper.foreground.opacity(0.06))

                HStack(spacing: 8) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 12))
                        .foregroundStyle(SwooshNeonTokens.Accent.cyan.opacity(0.7))

                    Text("SSD:")
                        .font(.system(size: 11))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)

                    Text(String(format: "%.0f / %.0f GB", diskTotalGB - diskFreeGB, diskTotalGB))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text2)

                    Text("•")
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)

                    Text(String(format: "%.1f GB cached models", cachedModelsGB))
                        .font(.system(size: 11))
                        .foregroundStyle(cachedModelsGB > 10 ? VoltPaper.Chart.c4 : SwooshNeonTokens.Canvas.text3)

                    Spacer()

                    Button {
                        showCacheManager = true
                    } label: {
                        Label("Manage", systemImage: "trash.circle")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(VoltPaper.foreground.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(barColor.opacity(0.2), lineWidth: 0.5)
                )
        )
        .task {
            await loadDiskInfo()
        }
        .sheet(isPresented: $showCacheManager) {
            CacheManagerView()
                .frame(minWidth: 500, idealWidth: 600, minHeight: 500, idealHeight: 650)
        }
    }

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

    private func loadDiskInfo() async {
        // Disk free/total
        if let attrs = try? FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()
        ) {
            diskTotalGB = (attrs[.systemSize] as? Int64).map { Double($0) / 1_073_741_824 } ?? 0
            diskFreeGB = (attrs[.systemFreeSize] as? Int64).map { Double($0) / 1_073_741_824 } ?? 0
        }

        // Cached models estimate
        let cachePaths = [
            "\(NSHomeDirectory())/.ollama/models",
            "\(NSHomeDirectory())/.cache/huggingface/hub",
            "\(NSHomeDirectory())/.cache/mlx",
            "\(NSHomeDirectory())/.swoosh/models",
        ]
        var totalCached: Int64 = 0
        let fm = FileManager.default
        for path in cachePaths {
            guard fm.fileExists(atPath: path),
                  let enumerator = fm.enumerator(atPath: path) else { continue }
            while let file = enumerator.nextObject() as? String {
                let fullPath = (path as NSString).appendingPathComponent(file)
                if let attrs = try? fm.attributesOfItem(atPath: fullPath),
                   let size = attrs[.size] as? Int64 {
                    totalCached += size
                }
            }
        }
        cachedModelsGB = Double(totalCached) / 1_073_741_824
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Per-model memory bar
// ═══════════════════════════════════════════════════════════════════

public struct ModelMemoryBar: View {

    let memoryGB: Double
    let maxMemoryGB: Double
    let isCompatible: Bool

    public init(memoryGB: Double, maxMemoryGB: Double) {
        self.memoryGB = memoryGB
        self.maxMemoryGB = maxMemoryGB
        self.isCompatible = memoryGB <= maxMemoryGB
    }

    private var ratio: Double {
        min(memoryGB / max(maxMemoryGB, 1), 1.0)
    }

    private var barColor: Color {
        if !isCompatible { return VoltPaper.destructive }
        if ratio > 0.7 { return VoltPaper.Chart.c4 }
        return SwooshNeonTokens.Accent.cyan
    }

    public var body: some View {
        HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(VoltPaper.foreground.opacity(0.06))
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(barColor.opacity(0.7))
                        .frame(width: max(geo.size.width * ratio, 2))
                }
            }
            .frame(width: 60, height: 4)

            Text(isCompatible
                 ? String(format: "%.1f GB", memoryGB)
                 : "⚠ \(String(format: "%.0f", memoryGB)) GB")
                .font(.system(size: 10, weight: isCompatible ? .regular : .semibold, design: .monospaced))
                .foregroundStyle(barColor)
                .frame(width: 60, alignment: .leading)
        }
    }
}
