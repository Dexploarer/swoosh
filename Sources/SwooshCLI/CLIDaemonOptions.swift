// SwooshCLI/CLIDaemonOptions.swift — Shared daemon connection options + JSON helper — 0.1A
//
// Lots of subcommands (goal, manifest, plugin, …) take the same
// host/port/config-dir flags to talk to the local daemon and turn them
// into a `SwooshAPIClient`. This file is the canonical implementation —
// new subcommands embed it via `@OptionGroup var daemon: DaemonConnectionOptions`.
// (Legacy commands still carry their own copies; they migrate opportunistically.)
//
// Also exposes `printAsJSON(_:)` so the new subcommands don't silently
// fall back to "{}" when UTF-8 decode of an otherwise-valid encoder
// output fails — failures throw a `ValidationError` the caller surfaces.

import ArgumentParser
import Foundation
import SwooshClient
import SwooshConfig

/// Encode `value` with `JSONEncoder.swooshCLI` and print as UTF-8.
/// Encode failures propagate via `try`; if UTF-8 decoding of the bytes
/// fails (should never happen with `JSONEncoder` output) we throw a
/// `ValidationError` so the caller sees the failure instead of a silent
/// "{}" placeholder.
func printAsJSON<T: Encodable>(_ value: T) throws {
    let data = try JSONEncoder.swooshCLI.encode(value)
    guard let output = String(data: data, encoding: .utf8) else {
        throw ValidationError("Failed to decode JSON encoder output as UTF-8.")
    }
    print(output)
}

struct DaemonConnectionOptions: ParsableArguments {
    @Option(name: .long, help: "Daemon host (default: 127.0.0.1).")
    var host: String = "127.0.0.1"

    @Option(name: .long, help: "Daemon port (default: 8787).")
    var port: Int = 8787

    @Option(name: .customLong("config-dir"), help: "State directory holding api_token (default: ~/.swoosh).")
    var configDirectory: String?

    init() {}

    /// Build a bearer-authenticated `SwooshAPIClient` from the resolved
    /// host/port and the API token at `<configDir>/api_token`. Throws
    /// `ValidationError` when the host/port can't be turned into a URL;
    /// missing-token is permitted because the client still surfaces an
    /// auth failure on the first request.
    func makeClient() throws -> SwooshAPIClient {
        let config = makeSwooshConfigStore(configDirectory: configDirectory)
        let token = (try? String(contentsOf: config.apiTokenFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: "http://\(host):\(port)") else {
            throw ValidationError("invalid host:port — \(host):\(port)")
        }
        return SwooshAPIClient(baseURL: baseURL, token: token)
    }
}
