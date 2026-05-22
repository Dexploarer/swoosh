// SwooshDaemon/CronAPIBridge.swift — Cron store ↔ HTTP API
//
// CRUD on `FileCronJobStore` plus a force-run that goes through the
// same `CronScheduler` + executor closure the daemon's tick task uses.

import Foundation
import SwooshAPI
import SwooshClient
import SwooshCron

extension SwooshDaemon {

    static func cronJobSummary(_ job: CronJob) -> CronJobRecordSummary {
        CronJobRecordSummary(
            id: job.id,
            name: job.name,
            state: job.state.rawValue,
            enabled: job.enabled,
            nextRunAt: job.nextRunAt,
            lastRunAt: job.lastRunAt
        )
    }

    static func cronJobsAPIResponse(store: any CronJobStoring) async -> CronJobsResponse {
        let jobs = (try? await store.list()) ?? []
        return CronJobsResponse(jobs: jobs.map(cronJobSummary))
    }

    static func createCronJobResponse(
        store: any CronJobStoring,
        request: CronJobCreateRequest
    ) async throws -> CronJobMutationResponse {
        let trimmedName = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw APIError.badRequest("cron job name is empty")
        }
        guard !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw APIError.badRequest("cron job prompt is empty")
        }
        let schedule: CronSchedule
        do {
            schedule = try CronScheduleParser.parse(request.schedule)
        } catch {
            throw APIError.badRequest("invalid schedule: \(error.localizedDescription)")
        }
        let job = CronJob(
            name: trimmedName,
            prompt: request.prompt,
            schedule: schedule,
            skills: request.skills ?? [],
            enabledToolsets: request.enabledToolsets,
            enabled: request.enabled ?? true,
            model: request.model,
            provider: request.provider,
            workdir: request.workdir
        )
        try await store.save(job)
        return CronJobMutationResponse(job: cronJobSummary(job), message: "Cron job created.")
    }

    static func deleteCronJobResponse(
        store: any CronJobStoring,
        id: String
    ) async throws -> CronJobsResponse {
        guard try await store.get(idOrName: id) != nil else {
            throw APIError.notFound("cron job not found: \(id)")
        }
        try await store.delete(idOrName: id)
        return await cronJobsAPIResponse(store: store)
    }

    static func runCronJobResponse(
        scheduler: CronScheduler,
        store: any CronJobStoring,
        executor: @escaping CronAgentExecutor,
        id: String
    ) async throws -> CronJobMutationResponse {
        guard let job = try await store.get(idOrName: id) else {
            throw APIError.notFound("cron job not found: \(id)")
        }
        do {
            _ = try await scheduler.runNow(idOrName: id, executor: executor)
        } catch {
            throw APIError.badRequest("could not run cron job: \(error.localizedDescription)")
        }
        let refreshed = (try? await store.get(idOrName: id)) ?? job
        return CronJobMutationResponse(
            job: cronJobSummary(refreshed),
            message: "Cron job run dispatched."
        )
    }
}
