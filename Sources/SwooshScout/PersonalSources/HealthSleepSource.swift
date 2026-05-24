// SwooshScout/PersonalSources/HealthSleepSource.swift — 0.9S HealthKit sleep summary (iOS)
//
// HealthKit-backed sleep summary. iOS only — macOS has no HealthKit
// store. Reports average total sleep hours over the last week,
// aggregated. Per the module's aggregate-only contract, individual
// sleep sessions and bedtimes are NOT exported.

import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

public struct HealthSleepSource: ScoutSource {
    public let id = "health_sleep"
    public let displayName = "Sleep (HealthKit)"
    public let description = "Recent nightly sleep duration. iOS only; requires Health permissions."
    public let sensitivity = Sensitivity.high
    public let requiredPermissions = ["health.sleep.read"]

    public init() {}

    public func checkPermission() async throws -> SourcePermissionStatus {
        #if canImport(HealthKit) && os(iOS)
        guard HKHealthStore.isHealthDataAvailable() else { return .restricted }
        let store = HKHealthStore()
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return .restricted }
        switch store.authorizationStatus(for: type) {
        case .sharingAuthorized: return .granted
        case .sharingDenied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
        #else
        return .restricted
        #endif
    }

    public func requestPermission() async throws -> SourcePermissionStatus {
        #if canImport(HealthKit) && os(iOS)
        guard HKHealthStore.isHealthDataAvailable() else { return .restricted }
        let store = HKHealthStore()
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return .restricted }
        try await store.requestAuthorization(toShare: [], read: [type])
        return try await checkPermission()
        #else
        return .restricted
        #endif
    }

    public func scan(progress: ScanProgress) async throws -> [ScoutRecord] {
        #if canImport(HealthKit) && os(iOS)
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let store = HKHealthStore()
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }
        // Count every staged "asleep" bucket so the summary doesn't
        // silently miss users whose data carries asleepCore/asleepDeep/
        // asleepREM (the common case on modern iPhones / watchOS).
        var asleepValues: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue]
        if #available(iOS 16.0, *) {
            asleepValues.insert(HKCategoryValueSleepAnalysis.asleepCore.rawValue)
            asleepValues.insert(HKCategoryValueSleepAnalysis.asleepDeep.rawValue)
            asleepValues.insert(HKCategoryValueSleepAnalysis.asleepREM.rawValue)
        }
        let asleepSamples = samples.filter { asleepValues.contains($0.value) }
        let totalAsleep = asleepSamples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        // Divide by the number of distinct calendar days that carry an
        // asleep sample (not a hardcoded 7), so a freshly-paired Health
        // store doesn't report a misleadingly low average.
        let cal = Calendar.current
        let daysWithData = Set(asleepSamples.map { cal.startOfDay(for: $0.startDate) }).count
        let denominator = max(1, daysWithData)
        let avgPerNight = totalAsleep / Double(denominator)
        let hours = avgPerNight / 3600.0
        return [
            ScoutRecord(
                sourceID: id, kind: .healthSleep, sensitivity: .high,
                content: "Average sleep over the last week: \(String(format: "%.1f", hours)) h/night.",
                metadata: ["avg_hours": String(format: "%.2f", hours)]
            )
        ]
        #else
        return []
        #endif
    }
}
