// SwooshDoctor/DoctorCheckIDs.swift — 0.9B Canonical check identifiers
//
// Every built-in `DoctorCheck.id` lives here as a typed constant so
// `DoctorReport.optimizationRecommendations` and any other consumer that
// switches on a check ID is caught by the compiler when a check is
// renamed. Previously the IDs were string literals in two places
// (the `DoctorCheck` conformances and the optimizer's heuristics) and
// could drift silently — a rename in `*Checks.swift` would just stop
// matching in the recommendations block.

import Foundation

public enum DoctorCheckID {

    // Installation
    public static let platform        = "sys.platform"
    public static let disk            = "sys.disk"
    public static let swooshDirectory = "sys.swoosh_dir"
    public static let memory          = "perf.memory"

    // Daemon
    public static let runtimeReadiness = "runtime.readiness"

    // Config
    public static let configFile = "config.file"
    public static let modelConfig = "config.model"
    public static let tokenBudget = "perf.budget"

    // Secrets
    public static let keychainAccess  = "secrets.keychain"
    public static let providerKeys    = "secrets.providers"

    // Model
    public static let providerReachability = "model.reachability"
    public static let localModel           = "model.local"

    // Storage
    public static let storageSize       = "storage.size"
    public static let checkpointCleanup = "storage.checkpoints"

    // Privacy
    public static let logPrivacy = "privacy.logs"

    /// Every canonical ID. Used by tests to confirm no check struct drifts
    /// away from this catalogue.
    public static let all: [String] = [
        platform, disk, swooshDirectory, memory,
        runtimeReadiness,
        configFile, modelConfig, tokenBudget,
        keychainAccess, providerKeys,
        providerReachability, localModel,
        storageSize, checkpointCleanup,
        logPrivacy,
    ]
}
