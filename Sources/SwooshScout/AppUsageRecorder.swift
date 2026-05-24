// SwooshScout/AppUsageRecorder.swift — 0.9S macOS app-focus history recorder
//
// The Mac equivalent of iOS Screen Time. NSWorkspace fires a
// notification every time the frontmost app changes; we accumulate
// (app, start, end) tuples and append them to ~/.swoosh/app-usage.jsonl
// so the AppUsageSource can summarise on demand.
//
// On iOS, Screen Time data lives in `DeviceActivity` /
// `FamilyControls`. That requires entitlements the current build
// doesn't carry — once the iOS app picks them up, an iOS-specific
// recorder lands alongside this one. Until then, AppUsageSource on
// iOS returns no records (the source is gated by permission anyway).

import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// One contiguous focus session for an app — appended as one JSONL line.
public struct AppFocusEvent: Codable, Sendable, Identifiable {
    public let id: String
    public let bundleID: String
    public let displayName: String
    public let startedAt: Date
    public let endedAt: Date

    public var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }

    public init(
        bundleID: String,
        displayName: String,
        startedAt: Date,
        endedAt: Date
    ) {
        self.id = UUID().uuidString
        self.bundleID = bundleID
        self.displayName = displayName
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

/// Records `AppFocusEvent`s to a JSONL log while the daemon runs. macOS
/// only — iOS lacks an equivalent unrestricted API. The recorder caps
/// the log at `maxLogBytes`; older entries are dropped on rotation so
/// disk pressure stays bounded.
public actor AppUsageRecorder {
    public let logURL: URL
    public let maxLogBytes: Int

    private var currentBundleID: String?
    private var currentDisplayName: String?
    private var currentStarted: Date?
    private let signalStore: PersonalizationSignalStore?
    private let dateFormatter: ISO8601DateFormatter
    #if canImport(AppKit)
    private var notificationToken: NSObjectProtocol?
    #endif

    public init(
        logURL: URL = AppUsageRecorder.defaultLogURL(),
        maxLogBytes: Int = 2 * 1024 * 1024,
        signalStore: PersonalizationSignalStore? = nil
    ) {
        self.logURL = logURL
        self.maxLogBytes = maxLogBytes
        self.signalStore = signalStore
        self.dateFormatter = ISO8601DateFormatter()
        self.dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    public static func defaultLogURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swoosh/app-usage.jsonl", isDirectory: false)
    }

    /// Begin recording. Idempotent — safe to call multiple times.
    /// On non-macOS platforms this returns without starting a recorder.
    public func start() async {
        #if canImport(AppKit)
        await ensureLogDirectory()
        // Seed from the current frontmost app so the first session has a
        // proper `startedAt`.
        if let app = NSWorkspace.shared.frontmostApplication {
            currentBundleID = app.bundleIdentifier ?? "unknown"
            currentDisplayName = app.localizedName ?? "Unknown"
            currentStarted = Date()
        }

        // Hook the activate notification. NSWorkspace's notification
        // center delivers on whatever queue posted, so we hop onto the
        // actor explicitly.
        let center = NSWorkspace.shared.notificationCenter
        notificationToken = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            let runningApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            Task { await self.handleActivation(app: runningApp) }
        }
        #endif
    }

    /// Stop recording and flush the current session to disk.
    public func stop() async {
        #if canImport(AppKit)
        if let token = notificationToken {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            notificationToken = nil
        }
        await flushCurrent(endingAt: Date())
        #endif
    }

    #if canImport(AppKit)
    private func handleActivation(app: NSRunningApplication?) async {
        guard let app else { return }
        let newBundle = app.bundleIdentifier ?? "unknown"
        if newBundle == currentBundleID { return }
        await flushCurrent(endingAt: Date())
        currentBundleID = newBundle
        currentDisplayName = app.localizedName ?? "Unknown"
        currentStarted = Date()
    }
    #endif

    private func flushCurrent(endingAt: Date) async {
        guard let bundleID = currentBundleID,
              let displayName = currentDisplayName,
              let started = currentStarted else { return }
        // Ignore sessions shorter than a second — likely Spotlight /
        // launcher fly-throughs the user didn't actually "use."
        if endingAt.timeIntervalSince(started) < 1.0 {
            currentStarted = nil
            return
        }
        let event = AppFocusEvent(
            bundleID: bundleID,
            displayName: displayName,
            startedAt: started,
            endedAt: endingAt
        )
        await append(event: event)
        await appendSignal(for: event)
        currentStarted = nil
    }

    private func append(event: AppFocusEvent) async {
        do {
            await ensureLogDirectory()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let line = try encoder.encode(event) + Data("\n".utf8)
            let handle = try fileHandleForAppend()
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.close()
            try rotateIfNeeded()
        } catch {
            // Best-effort — failing to record one event must not bring
            // the daemon down. Swallow.
        }
    }

    private func ensureLogDirectory() async {
        let dir = logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            _ = FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
    }

    private func appendSignal(for event: AppFocusEvent) async {
        guard let signalStore else { return }
        try? await signalStore.append(PersonalizationSignal(
            kind: .appFocus,
            label: event.displayName,
            occurredAt: event.endedAt,
            weight: max(1, event.duration / 60),
            metadata: [
                "bundle_id": event.bundleID,
                "duration_seconds": String(Int(event.duration)),
            ]
        ))
    }

    private func fileHandleForAppend() throws -> FileHandle {
        try FileHandle(forWritingTo: logURL)
    }

    /// Rotate the log when it grows past `maxLogBytes` by dropping the
    /// oldest 25% of lines.
    private func rotateIfNeeded() throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: logURL.path)
        guard let size = attrs[.size] as? Int, size > maxLogBytes else { return }
        let data = try Data(contentsOf: logURL)
        guard let text = String(data: data, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let dropCount = max(1, lines.count / 4)
        let kept = lines.dropFirst(dropCount).joined(separator: "\n")
        try kept.write(to: logURL, atomically: true, encoding: .utf8)
    }
}
