// SwooshDaemon/DaemonHost.swift — 0.1A In-process daemon handle + errors
//
// The daemon is no longer a separate `swooshd` binary — `SwooshDaemon.start()`
// boots the kernel + HTTP server inside the host process (the macOS app) and
// returns this handle. The host retains it for its lifetime; teardown is the
// process exiting (the app and the agent runtime now share one lifecycle, so
// there is no in-session daemon restart to shut down gracefully).

import Foundation

/// Live handle to the in-process agent runtime + HTTP server. The host
/// retains it opaquely; the internals (runtime schedulers, server task)
/// are package-internal since callers only need to keep it alive.
public struct DaemonHandle: @unchecked Sendable {
    /// Background schedulers/recorders started at boot (cron, manifest,
    /// goal autopilot, scout). Held so they aren't torn down early.
    let runtime: DaemonRuntime
    /// The Hummingbird server task. Runs until the process exits.
    let serverTask: Task<Void, Error>
    /// Bound address, exposed for host-side logging / health probes.
    public let host: String
    public let port: Int

    init(runtime: DaemonRuntime, serverTask: Task<Void, Error>, host: String, port: Int) {
        self.runtime = runtime
        self.serverTask = serverTask
        self.host = host
        self.port = port
    }
}

/// Fatal boot failures. In the standalone binary these were `exit(1)`;
/// in-process they throw so the host can surface the error instead of
/// killing the whole app.
public enum DaemonError: Error, LocalizedError {
    case tokenResolutionFailed(Error)
    case kernelBuildFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .tokenResolutionFailed(let e): return "Failed to resolve API token: \(e)"
        case .kernelBuildFailed(let e): return "Failed to build agent kernel: \(e)"
        }
    }
}
