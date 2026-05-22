// Tests/SwooshAPITests/FirewallCronRoutesTests.swift — Tier 1
//
// Wire-level coverage for /api/firewall/* and /api/cron/* CRUD.

import HummingbirdTesting
import HTTPTypes
import Testing
import Foundation
@testable import SwooshAPI
import SwooshClient

@Suite("Firewall routes")
struct FirewallRoutesTests {

    @Test("GET /api/firewall/grants returns the source list")
    func listGrants() async throws {
        let sources = SwooshAPIRuntimeSources(
            firewallGrants: {
                FirewallResponse(granted: ["fileRead", "toolRead"], denied: ["walletSign"])
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/firewall/grants", method: .get,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let body = try fwTestDecoder().decode(FirewallResponse.self, from: Data(buffer: response.body))
                #expect(body.granted.contains("fileRead"))
                #expect(body.denied == ["walletSign"])
            }
        }
    }

    @Test("POST /api/firewall/grants accepts a grant")
    func postGrant() async throws {
        let received = FWGrantBox()
        let sources = SwooshAPIRuntimeSources(
            updateFirewall: { request in
                await received.set(request)
                return FirewallMutationResponse(
                    firewall: FirewallResponse(granted: [request.permission], denied: []),
                    message: "Granted \(request.permission)."
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            let body = try JSONEncoder().encode(FirewallGrantRequest(permission: "fileRead"))
            try await client.execute(
                uri: "/api/firewall/grants", method: .post,
                headers: [.authorization: "Bearer secret", .contentType: "application/json"],
                body: .init(bytes: body)
            ) { response in
                #expect(response.status == .ok)
                let decoded = try fwTestDecoder().decode(FirewallMutationResponse.self, from: Data(buffer: response.body))
                #expect(decoded.firewall.granted.contains("fileRead"))
            }
        }
        #expect(await received.value?.permission == "fileRead")
        #expect(await received.value?.decision == "grant")
    }

    @Test("DELETE /api/firewall/grants/:permission revokes")
    func revoke() async throws {
        let captured = FWPermissionBox()
        let sources = SwooshAPIRuntimeSources(
            revokeFirewall: { permission in
                await captured.set(permission)
                return FirewallResponse(granted: [], denied: [])
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/firewall/grants/fileRead", method: .delete,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let body = try fwTestDecoder().decode(FirewallResponse.self, from: Data(buffer: response.body))
                #expect(body.granted.isEmpty)
            }
        }
        #expect(await captured.value == "fileRead")
    }

    @Test("POST /api/firewall/check returns grant status")
    func check() async throws {
        let sources = SwooshAPIRuntimeSources(
            checkFirewall: { request in
                FirewallCheckResponse(
                    permission: request.permission,
                    granted: request.permission == "fileRead",
                    denied: false
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            let body = try JSONEncoder().encode(FirewallCheckRequest(permission: "fileRead"))
            try await client.execute(
                uri: "/api/firewall/check", method: .post,
                headers: [.authorization: "Bearer secret", .contentType: "application/json"],
                body: .init(bytes: body)
            ) { response in
                #expect(response.status == .ok)
                let decoded = try fwTestDecoder().decode(FirewallCheckResponse.self, from: Data(buffer: response.body))
                #expect(decoded.granted)
            }
        }
    }
}

@Suite("Cron CRUD routes")
struct CronCRUDRoutesTests {

    @Test("GET /api/cron returns the source list")
    func listCron() async throws {
        let sources = SwooshAPIRuntimeSources(
            cronJobs: {
                CronJobsResponse(jobs: [sampleCronJob(id: "a"), sampleCronJob(id: "b")])
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/cron", method: .get,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let body = try fwTestDecoder().decode(CronJobsResponse.self, from: Data(buffer: response.body))
                #expect(body.jobs.map(\.id) == ["a", "b"])
            }
        }
    }

    @Test("POST /api/cron creates a job")
    func createCron() async throws {
        let received = CronCreateBox()
        let sources = SwooshAPIRuntimeSources(
            createCronJob: { request in
                await received.set(request)
                return CronJobMutationResponse(
                    job: sampleCronJob(id: "new"),
                    message: "Cron job created."
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            let body = try JSONEncoder().encode(CronJobCreateRequest(
                name: "daily-report",
                prompt: "Summarize yesterday",
                schedule: "daily at 9am"
            ))
            try await client.execute(
                uri: "/api/cron", method: .post,
                headers: [.authorization: "Bearer secret", .contentType: "application/json"],
                body: .init(bytes: body)
            ) { response in
                #expect(response.status == .ok)
                let decoded = try fwTestDecoder().decode(CronJobMutationResponse.self, from: Data(buffer: response.body))
                #expect(decoded.job.id == "new")
            }
        }
        #expect(await received.value?.name == "daily-report")
        #expect(await received.value?.schedule == "daily at 9am")
    }

    @Test("DELETE /api/cron/:id removes the job")
    func deleteCron() async throws {
        let captured = CronIDBox()
        let sources = SwooshAPIRuntimeSources(
            deleteCronJob: { id in
                await captured.set(id)
                return CronJobsResponse(jobs: [])
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/cron/abc", method: .delete,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let body = try fwTestDecoder().decode(CronJobsResponse.self, from: Data(buffer: response.body))
                #expect(body.jobs.isEmpty)
            }
        }
        #expect(await captured.value == "abc")
    }

    @Test("POST /api/cron/:id/run forces a run")
    func runCron() async throws {
        let captured = CronIDBox()
        let sources = SwooshAPIRuntimeSources(
            runCronJob: { id in
                await captured.set(id)
                return CronJobMutationResponse(
                    job: sampleCronJob(id: id),
                    message: "Cron job run dispatched."
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/cron/abc/run", method: .post,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let decoded = try fwTestDecoder().decode(CronJobMutationResponse.self, from: Data(buffer: response.body))
                #expect(decoded.message.contains("dispatched"))
            }
        }
        #expect(await captured.value == "abc")
    }
}

private func sampleCronJob(id: String) -> CronJobRecordSummary {
    CronJobRecordSummary(
        id: id,
        name: "cron-\(id)",
        state: "scheduled",
        enabled: true,
        nextRunAt: Date(timeIntervalSince1970: 1_700_000_000),
        lastRunAt: nil
    )
}

private actor FWGrantBox {
    private var stored: FirewallGrantRequest?
    func set(_ value: FirewallGrantRequest) { stored = value }
    var value: FirewallGrantRequest? { stored }
}

private actor FWPermissionBox {
    private var stored: String?
    func set(_ value: String) { stored = value }
    var value: String? { stored }
}

private actor CronCreateBox {
    private var stored: CronJobCreateRequest?
    func set(_ value: CronJobCreateRequest) { stored = value }
    var value: CronJobCreateRequest? { stored }
}

private actor CronIDBox {
    private var stored: String?
    func set(_ value: String) { stored = value }
    var value: String? { stored }
}

private func fwTestDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}
