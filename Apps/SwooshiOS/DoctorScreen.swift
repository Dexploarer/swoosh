// Apps/SwooshiOS/DoctorScreen.swift — 0.5A iOS diagnostics surface
//
// Renders the daemon's `GET /api/doctor` report — list of category-keyed
// checks, status badge per row, suggested fix commands, and the optimizer
// recommendation list. Pattern mirrors `CronScreen.swift`: full-bleed
// loading/empty/error states on first paint, inline notice afterwards,
// pull-to-refresh + `.task`-driven initial load, single SwooshClient
// import (no SwooshKit).

import SwiftUI
import SwooshClient

struct DoctorScreen: View {
    @Environment(ClientSession.self) private var session
    @State private var report: DoctorReportResponse?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var hasLoadedOnce = false

    var body: some View {
        Group {
            if !session.isPaired {
                ContentUnavailableView(
                    "Not paired",
                    systemImage: "link.badge.plus",
                    description: Text("Pair with swooshd from Settings → Pairing to run diagnostics.")
                )
            } else if isLoading && !hasLoadedOnce {
                ProgressView("Running diagnostics…").controlSize(.large)
            } else if report == nil, let errorText, hasLoadedOnce {
                ContentUnavailableView {
                    Label("Couldn't run diagnostics", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorText)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            } else if let report {
                reportList(report)
            }
        }
        .navigationTitle("Diagnostics")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(!session.isPaired || isLoading)
                .accessibilityLabel("Refresh diagnostics")
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - List

    @ViewBuilder
    private func reportList(_ report: DoctorReportResponse) -> some View {
        List {
            summarySection(report)
            if let errorText {
                Section {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            ForEach(groupedChecks(report.checks), id: \.0) { (category, checks) in
                Section(category.capitalized) {
                    ForEach(checks) { check in
                        DoctorCheckRow(check: check)
                    }
                }
            }
            if !report.recommendations.isEmpty {
                Section("Recommendations") {
                    ForEach(Array(report.recommendations.enumerated()), id: \.offset) { _, rec in
                        Text(rec)
                            .font(.footnote)
                    }
                }
            }
            Section {
                Text("Generated \(report.createdAt.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func summarySection(_ report: DoctorReportResponse) -> some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: report.isHealthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundStyle(report.isHealthy ? .green : .orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.isHealthy ? "Healthy" : "Needs attention")
                        .font(.body.weight(.semibold))
                    HStack(spacing: 10) {
                        countChip("\(report.summary.passed)", color: .green, label: "pass")
                        if report.summary.warnings > 0 {
                            countChip("\(report.summary.warnings)", color: .orange, label: "warn")
                        }
                        if report.summary.failures > 0 {
                            countChip("\(report.summary.failures)", color: .red, label: "fail")
                        }
                        if report.summary.skipped > 0 {
                            countChip("\(report.summary.skipped)", color: .secondary, label: "skip")
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
    }

    private func countChip(_ value: String, color: Color, label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.subheadline.weight(.bold)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    /// Stable category ordering so the rendered list doesn't shuffle
    /// between refreshes when the daemon reorders categories.
    private func groupedChecks(_ checks: [DoctorCheckSummary]) -> [(String, [DoctorCheckSummary])] {
        let groups = Dictionary(grouping: checks, by: \.category)
        return groups.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    // MARK: - Networking

    private func load() async {
        guard let client = session.client() else { return }
        isLoading = true
        defer { isLoading = false; hasLoadedOnce = true }
        do {
            report = try await client.doctorReport()
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Row

private struct DoctorCheckRow: View {
    let check: DoctorCheckSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                statusBadge
                Text(check.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
            }
            if let message = check.message, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            if let fix = check.fixCommand, !fix.isEmpty {
                Text("Fix: \(fix)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusBadge: some View {
        let (symbol, tint): (String, Color) = {
            switch check.status.lowercased() {
            case "pass":    return ("checkmark", .green)
            case "warning": return ("exclamationmark", .orange)
            case "fail":    return ("xmark", .red)
            case "skipped": return ("minus", .secondary)
            default:        return ("questionmark", .secondary)
            }
        }()
        Image(systemName: symbol)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(tint, in: Circle())
            .accessibilityLabel(check.status)
    }
}
