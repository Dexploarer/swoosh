// SwooshCLI/DaemonPairCommand.swift — iOS pairing guidance subcommand — 0.4A

import ArgumentParser
import Foundation

struct DaemonPairCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "pair", abstract: "Show secure iOS pairing guidance.")

    @Option(name: .long, help: "Host URL (defaults to system IP on port 8787)")
    var host: String?

    @Option(name: .long, help: "Port (defaults to 8787)")
    var port: Int = 8787

    @Option(name: .long, help: "Config directory (defaults to ~/.swoosh)")
    var configDirectory: String?

    func run() async throws {
        let hostURL = host
            ?? CLIPairing.localIPAddress().map { "http://\($0):\(port)" }
            ?? "http://127.0.0.1:\(port)"
        print()
        print("Secure iOS pairing now runs from the Detour Mac onboarding screen.")
        print("Open Detour on this Mac, restart onboarding if needed, and scan the QR code shown there.")
        print("That flow uses a short-lived pairing code, a confirmation code, and a per-device token.")
        print("Host candidate: \(hostURL)")
        print()
    }
}
