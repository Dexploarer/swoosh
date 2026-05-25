// SwooshCLI/DaemonPairCommand.swift — iOS pairing QR code subcommand — 0.4A
//
// `swoosh daemon pair` mints (or reads) the daemon bearer token, picks a
// reachable host URL, and prints the deep-link QR code the iOS app
// scans on first launch. QR rendering and local-IP discovery live in
// CLIPairing.swift; bearer-token generation lives in CLIBearerToken.swift.

import ArgumentParser
import Foundation

struct DaemonPairCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "pair", abstract: "Generate QR code for iOS pairing.")

    @Option(name: .long, help: "Host URL (defaults to system IP on port 8787)")
    var host: String?

    @Option(name: .long, help: "Port (defaults to 8787)")
    var port: Int = 8787

    @Option(name: .long, help: "Config directory (defaults to ~/.swoosh)")
    var configDirectory: String?

    func run() async throws {
        let config = makeSwooshConfigStore(configDirectory: configDirectory)
        let tokenPath = config.apiTokenFile

        let token: String
        do {
            token = try ensureBearerTokenFile(at: tokenPath)
        } catch {
            print("✗ Failed to mint or read API token at \(tokenPath.path): \(error)")
            return
        }

        let hostURL: String
        if let customHost = host {
            hostURL = customHost
        } else if let localIP = CLIPairing.localIPAddress() {
            hostURL = "http://\(localIP):\(port)"
        } else {
            hostURL = "http://127.0.0.1:\(port)"
        }

        guard let payload = CLIPairing.pairingPayload(host: hostURL, token: token) else {
            print("✗ Failed to create pairing data")
            return
        }

        print("╔═══════════════════════════════════════════╗")
        print("║     iOS Pairing QR Code                  ║")
        print("╚═══════════════════════════════════════════╝")
        print()
        print("Scan this QR code with the Swoosh iOS app to pair:")
        print()

        if let qrCode = CLIPairing.generateQRCode(from: payload) {
            print(qrCode)
            print()
        } else {
            print("✗ Failed to generate QR code")
            print()
            print("Manual pairing information:")
            print("  Host: \(hostURL)")
            print("  Token: \(token)")
            return
        }

        print("Or enter manually in iOS app:")
        print("  Host: \(hostURL)")
        print("  Token: \(token)")
        print()
        print("⚠️  Keep this QR code private - it grants full access to your agent")
    }
}
