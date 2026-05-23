// Apps/SwooshiOS/CronScreen.swift — 0.5A iOS cron job manager
//
// Lists, creates, runs, and deletes scheduled jobs against the daemon's
// `/api/cron/*` endpoints via `SwooshAPIClient+Cron`. State + transport
// follow the same pattern as `ChannelsScreen` / `CapabilityPickerScreen`:
// `@Environment(ClientSession.self)` for the paired client, full-bleed
// loading/empty/error states on first paint, inline `ContentUnavailableView`
// otherwise. The create form is a sheet — natural-language schedule
// string ("every 5 minutes" / "daily at 9am"), parsed server-side by
// `CronScheduleParser`.

import SwiftUI
import SwooshClient

struct CronScreen: View {
    @Environment(ClientSession.self) private var session
    @State private var jobs: [CronJobRecordSummary] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var hasLoadedOnce = false
    @State private var creating = false
    @State private var runningJobID: String?

    var body: some View {
        Group {
            if !session.isPaired {
                ContentUnavailableView(
                    "Not paired",
                    systemImage: "link.badge.plus",
                    description: Text("Pair with swooshd from Settings → Pairing to manage scheduled jobs.")
                )
            } else if isLoading && !hasLoadedOnce {
                ProgressView("Loading jobs…").controlSize(.large)
            } else if jobs.isEmpty, let errorText, hasLoadedOnce {
                ContentUnavailableView {
                    Label("Couldn't load jobs", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorText)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            } else if jobs.isEmpty, hasLoadedOnce {
                ContentUnavailableView {
                    Label("No scheduled jobs", systemImage: "calendar.badge.clock")
                } description: {
                    Text("Tap + to add a job that runs on a schedule and wakes the agent automatically.")
                }
            } else {
                jobList
            }
        }
        .navigationTitle("Scheduled Jobs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    creating = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!session.isPaired)
                .accessibilityLabel("Add scheduled job")
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $creating) {
            CronJobCreateSheet(onCreated: { newJob in
                jobs.insert(newJob, at: 0)
                Task { await load() }
            })
        }
    }

    // MARK: - List

    @ViewBuilder
    private var jobList: some View {
        List {
            if let errorText {
                Section {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            Section {
                ForEach(jobs) { job in
                    CronJobRow(
                        job: job,
                        isRunning: runningJobID == job.id,
                        onRun: { Task { await runJob(job) } }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await deleteJob(job) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } footer: {
                Text("Disabled jobs stay in the list but won't fire on their schedule. Pull to refresh.")
                    .font(.footnote)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Networking

    private func load() async {
        guard let client = session.client() else { return }
        isLoading = true
        defer { isLoading = false; hasLoadedOnce = true }
        do {
            let response = try await client.cronJobs()
            jobs = response.jobs
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func runJob(_ job: CronJobRecordSummary) async {
        guard let client = session.client() else { return }
        runningJobID = job.id
        defer { runningJobID = nil }
        do {
            _ = try await client.runCronJob(id: job.id)
            await load()
        } catch {
            errorText = "Couldn't run \(job.name): \(error.localizedDescription)"
        }
    }

    private func deleteJob(_ job: CronJobRecordSummary) async {
        guard let client = session.client() else { return }
        do {
            let response = try await client.deleteCronJob(id: job.id)
            jobs = response.jobs
            errorText = nil
        } catch {
            errorText = "Couldn't delete \(job.name): \(error.localizedDescription)"
        }
    }
}

// MARK: - Row

private struct CronJobRow: View {
    let job: CronJobRecordSummary
    let isRunning: Bool
    let onRun: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(job.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    stateBadge
                    if let next = job.nextRunAt, job.enabled {
                        Text("Next \(next.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if let last = job.lastRunAt {
                        Text("Last \(last.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            Button(action: onRun) {
                if isRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "play.fill")
                }
            }
            .buttonStyle(.borderless)
            .disabled(isRunning)
            .accessibilityLabel("Run \(job.name) now")
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var stateBadge: some View {
        let (label, tint): (String, Color) = {
            switch job.state.lowercased() {
            case "scheduled": return (job.enabled ? "Scheduled" : "Paused", job.enabled ? .green : .gray)
            case "running":   return ("Running", .blue)
            case "completed": return ("Completed", .secondary)
            case "failed":    return ("Failed", .red)
            case "paused":    return ("Paused", .gray)
            default:          return (job.state, .secondary)
            }
        }()
        Text(label.uppercased())
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
    }
}

// MARK: - Create sheet

private struct CronJobCreateSheet: View {
    @Environment(ClientSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let onCreated: (CronJobRecordSummary) -> Void

    @State private var name = ""
    @State private var prompt = ""
    @State private var schedule = "every 30 minutes"
    @State private var enabled = true
    @State private var submitting = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Morning summary", text: $name)
                        .textInputAutocapitalization(.words)
                }
                Section("Prompt") {
                    TextField("What should the agent do when it wakes?", text: $prompt, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
                Section {
                    TextField("Schedule", text: $schedule)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("Enabled", isOn: $enabled)
                } header: {
                    Text("Schedule")
                } footer: {
                    Text("Natural language: \"every 5 minutes\", \"daily at 9am\", \"every monday at 10am\", or a 5-field cron expression like \"0 9 * * *\".")
                        .font(.footnote)
                }
                if let errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("New scheduled job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { await submit() }
                    }
                    .disabled(submitting || trimmedName.isEmpty || trimmedPrompt.isEmpty || trimmedSchedule.isEmpty)
                }
            }
            .overlay {
                if submitting {
                    ProgressView().controlSize(.large)
                }
            }
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedPrompt: String { prompt.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedSchedule: String { schedule.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func submit() async {
        guard let client = session.client() else {
            errorText = "Not paired."
            return
        }
        submitting = true
        defer { submitting = false }
        let request = CronJobCreateRequest(
            name: trimmedName,
            prompt: trimmedPrompt,
            schedule: trimmedSchedule,
            enabled: enabled
        )
        do {
            let response = try await client.createCronJob(request)
            onCreated(response.job)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
