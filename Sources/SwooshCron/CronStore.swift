// SwooshCron/CronStore.swift — Atomic file-backed cron storage
import Foundation

public protocol CronJobStoring: Sendable {
    func save(_ job: CronJob) async throws
    func update(_ job: CronJob) async throws
    func get(idOrName: String) async throws -> CronJob?
    func delete(idOrName: String) async throws
    func list() async throws -> [CronJob]
    func saveRun(_ run: CronRunRecord) async throws
    func listRuns(jobID: String, limit: Int?) async throws -> [CronRunRecord]
    func latestSuccessfulOutput(jobIDOrName: String) async throws -> String?
}

public actor FileCronJobStore: CronJobStoring {
    private let jobsURL: URL
    private let outputDirectory: URL
    private var loaded = false
    private var jobs: [String: CronJob] = [:]
    private var runs: [String: [CronRunRecord]] = [:]

    public init(root: URL? = nil) {
        let base = root ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swoosh/cron", isDirectory: true)
        self.jobsURL = base.appendingPathComponent("jobs.json")
        self.outputDirectory = base.appendingPathComponent("output", isDirectory: true)
    }

    public func save(_ job: CronJob) async throws {
        try ensureLoaded()
        jobs[job.id] = job
        try persist()
    }

    public func update(_ job: CronJob) async throws {
        try ensureLoaded()
        guard jobs[job.id] != nil else { throw CronStoreError.notFound(job.id) }
        var updated = job
        updated.updatedAt = Date()
        jobs[job.id] = updated
        try persist()
    }

    public func get(idOrName: String) async throws -> CronJob? {
        try ensureLoaded()
        return jobs[idOrName] ?? jobs.values.first { $0.name == idOrName }
    }

    public func delete(idOrName: String) async throws {
        try ensureLoaded()
        if jobs.removeValue(forKey: idOrName) == nil,
           let id = jobs.values.first(where: { $0.name == idOrName })?.id {
            jobs.removeValue(forKey: id)
        }
        try persist()
    }

    public func list() async throws -> [CronJob] {
        try ensureLoaded()
        return jobs.values.sorted { ($0.nextRunAt ?? .distantFuture) < ($1.nextRunAt ?? .distantFuture) }
    }

    public func saveRun(_ run: CronRunRecord) async throws {
        try ensureLoaded()
        var list = runs[run.jobID] ?? []
        list.append(run)
        runs[run.jobID] = list
        try persistRun(run)
    }

    public func listRuns(jobID: String, limit: Int?) async throws -> [CronRunRecord] {
        try ensureLoaded()
        var list = runs[jobID] ?? []
        list.sort { $0.startedAt > $1.startedAt }
        if let limit { list = Array(list.prefix(limit)) }
        return list
    }

    public func latestSuccessfulOutput(jobIDOrName: String) async throws -> String? {
        try ensureLoaded()
        guard let job = try await get(idOrName: jobIDOrName) else { return nil }
        let run = (runs[job.id] ?? [])
            .filter { $0.status == .ok }
            .sorted { $0.startedAt > $1.startedAt }
            .first
        guard let outputPath = run?.outputPath else { return nil }
        return try? String(contentsOfFile: outputPath, encoding: .utf8)
    }

    public func outputPath(jobID: String, date: Date = Date()) throws -> URL {
        let formatter = ISO8601DateFormatter()
        let stamp = formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
        let dir = outputDirectory.appendingPathComponent(jobID, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(stamp).md")
    }

    private func ensureLoaded() throws {
        guard !loaded else { return }
        try FileManager.default.createDirectory(at: jobsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: jobsURL.path) {
            let data = try Data(contentsOf: jobsURL)
            let snapshot = try JSONDecoder.swooshCron.decode(CronStoreSnapshot.self, from: data)
            jobs = Dictionary(uniqueKeysWithValues: snapshot.jobs.map { ($0.id, $0) })
            runs = Dictionary(grouping: snapshot.runs, by: \.jobID)
        }
        loaded = true
    }

    private func persist() throws {
        let snapshot = CronStoreSnapshot(
            jobs: jobs.values.sorted { $0.createdAt < $1.createdAt },
            runs: runs.values.flatMap { $0 }.sorted { $0.startedAt < $1.startedAt }
        )
        let data = try JSONEncoder.swooshCron.encode(snapshot)
        try data.write(to: jobsURL, options: .atomic)
    }

    private func persistRun(_ run: CronRunRecord) throws {
        try persist()
    }
}

private struct CronStoreSnapshot: Codable {
    let jobs: [CronJob]
    let runs: [CronRunRecord]
}

public enum CronStoreError: Error, Sendable, LocalizedError {
    case notFound(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let id): "cron job not found: \(id)"
        }
    }
}

extension JSONEncoder {
    static var swooshCron: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var swooshCron: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
