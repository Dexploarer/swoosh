// SwooshCLI/SwooshCommand.swift — CLI entry point + Doctor/Model/Daemon
//
// swoosh <subcommand>  — see subcommands below
// Split into: SetupCommands.swift, ChatAskCommands.swift, ScoutMemoryCommands.swift

import ArgumentParser
import SwooshKit
import SwooshConfig
import SwooshDoctor
import SwooshProviders
import SwooshSecrets
import SwooshTools
import SwooshChatSDK
import Foundation
#if canImport(CoreImage)
import CoreImage
#endif
#if canImport(AppKit)
import AppKit
#endif
#if canImport(SystemConfiguration)
import SystemConfiguration
#endif

@main
struct SwooshCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swoosh",
        abstract: "Swift-native autonomous agent runtime.",
        version: "0.1.0",
        subcommands: [
            SetupCommand.self,
            AskCommand.self,
            DoctorCommand.self,
            ScoutCommand.self,
            MemoryCommand.self,
            ModelCommand.self,
            DaemonCommand.self,
            ChatCommand.self,
            SelfTestCommand.self,
            PermissionsCommand.self,
            ProviderCommand.self,
            SkillsCommand.self,
            CronCommand.self,
            TerminalCommand.self,
            ChatAdaptersCommand.self,
            CompletionsCommand.self,
        ],
        defaultSubcommand: ChatCommand.self
    )
}

// MARK: - Doctor

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "doctor", abstract: "Run comprehensive diagnostics.")

    @Flag(name: .long, help: "Attempt to fix detected issues.")
    var fix = false

    @Flag(name: .long, help: "Output as JSON.")
    var json = false

    @Option(name: .customLong("config-dir"), help: "State directory to inspect instead of ~/.swoosh.")
    var configDirectory: String?

    func run() async throws {
        let config = makeSwooshConfigStore(configDirectory: configDirectory)
        if fix {
            try config.ensureDirectories()
        }
        let runner = DoctorRunner()
        let result = await runner.runAll(context: DoctorContext(
            configPath: config.configFile.path,
            statePath: config.configDirectory.path,
            logPath: config.logsDir.path
        ))

        if json {
            print("{\"passed\": \(result.isHealthy), \"checks\": \(result.checks.count), \"failures\": \(result.summary.failures)}")
            return
        }

        print("Swoosh Doctor\n")

        var currentCategory = ""
        for check in result.checks {
            if check.category.rawValue != currentCategory {
                currentCategory = check.category.rawValue
                print("─── \(currentCategory) ───")
            }

            let icon: String
            let detail: String
            switch check.status {
            case .pass: icon = "✓"; detail = check.message ?? "passed"
            case .warning: icon = "○"; detail = check.message ?? "warning"
            case .fail: icon = "✗"; detail = check.message ?? "failed"
            case .skipped: icon = "-"; detail = check.message ?? "skipped"
            }

            print("  \(icon) \(check.title): \(detail)")
            if let f = check.fixCommand, icon == "✗" { print("    Fix: \(f)") }
        }

        print()
        if result.summary.failures == 0, result.summary.warnings == 0 {
            print("All checks passed. ✓")
        } else if result.summary.failures == 0 {
            print("\(result.summary.warnings) warning(s) found.")
        } else {
            print("\(result.summary.failures) issue(s) found.")
            if !fix { print("Run `swoosh doctor --fix` to attempt repairs.") }
        }
    }
}

// MARK: - Model

struct ModelCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "model", abstract: "Configure model providers.")

    @Flag(name: .long, help: "Test the current model configuration.")
    var test = false

    func run() async throws {
        if test {
            try await runProviderTests(provider: nil)
            return
        }

        print("Model provider setup\n")
        print("Recommended:")
        print("  1. Local MLX")
        print("  2. OpenAI")
        print("  3. Anthropic")
        print("  4. OpenRouter")
        print("\nAlready detected:")

        let hardware = HardwareDetector().detect()
        if hardware.hasAppleSilicon {
            let localModels = hardware.recommendedLocalModels.filter { $0.fits == .recommended || $0.fits == .feasible }
            print("  ✓ Apple Silicon — can run: \(localModels.map(\.sizeLabel).joined(separator: ", "))")
        }
        print("")
        try await ProviderListCommand().run()
    }
}

// MARK: - Daemon

struct DaemonCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "daemon",
        abstract: "Manage swooshd daemon.",
        subcommands: [DaemonInstallCommand.self, DaemonStartCommand.self, DaemonStopCommand.self, DaemonStatusCommand.self, DaemonPairCommand.self]
    )
}

struct DaemonInstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "install", abstract: "Install swooshd LaunchAgent.")
    func run() async throws {
        let plistPath = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/LaunchAgents/ai.swoosh.daemon.plist")

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>ai.swoosh.daemon</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/local/bin/swooshd</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardOutPath</key>
            <string>\(FileManager.default.homeDirectoryForCurrentUser.path)/.swoosh/logs/swooshd.log</string>
            <key>StandardErrorPath</key>
            <string>\(FileManager.default.homeDirectoryForCurrentUser.path)/.swoosh/logs/swooshd.err</string>
        </dict>
        </plist>
        """

        try plist.write(to: plistPath, atomically: true, encoding: .utf8)
        print("✓ LaunchAgent installed at \(plistPath.path)")
        print("  Run `swoosh daemon start` to start.")
    }
}

struct DaemonStartCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "start", abstract: "Start swooshd.")
    func run() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", "-w",
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/LaunchAgents/ai.swoosh.daemon.plist").path]
        try process.run()
        process.waitUntilExit()
        print(process.terminationStatus == 0 ? "✓ swooshd started" : "✗ Failed to start swooshd")
    }
}

struct DaemonStopCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "stop", abstract: "Stop swooshd.")
    func run() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload",
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/LaunchAgents/ai.swoosh.daemon.plist").path]
        try process.run()
        process.waitUntilExit()
        print(process.terminationStatus == 0 ? "✓ swooshd stopped" : "✗ Failed to stop swooshd")
    }
}

struct DaemonStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Check swooshd status.")
    func run() async throws {
        let plistPath = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/LaunchAgents/ai.swoosh.daemon.plist")
        guard FileManager.default.fileExists(atPath: plistPath.path) else {
            print("✗ LaunchAgent not installed")
            print("  Run: swoosh daemon install")
            return
        }
        print("✓ LaunchAgent installed")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list", "ai.swoosh.daemon"]
        process.standardOutput = Pipe()
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        print(process.terminationStatus == 0 ? "✓ swooshd is running" : "○ swooshd is not running\n  Run: swoosh daemon start")
    }
}

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

        // Generate token if it doesn't exist
        if !FileManager.default.fileExists(atPath: tokenPath.path) {
            let token = try generateBearerToken()
            try token.write(to: tokenPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenPath.path)
        }

        let tokenContent = try? String(contentsOf: tokenPath, encoding: .utf8)
        guard let token = tokenContent?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            print("✗ Failed to read API token from \(tokenPath.path)")
            return
        }

        // Determine host URL
        let hostURL: String
        if let customHost = host {
            hostURL = customHost
        } else {
            // Try to get local IP address
            if let localIP = getLocalIPAddress() {
                hostURL = "http://\(localIP):\(port)"
            } else {
                hostURL = "http://127.0.0.1:\(port)"
            }
        }

        // Create pairing data
        let pairingData = [
            "host": hostURL,
            "token": token
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: pairingData, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("✗ Failed to create pairing data")
            return
        }

        print("╔═══════════════════════════════════════════╗")
        print("║     iOS Pairing QR Code                  ║")
        print("╚═══════════════════════════════════════════╝")
        print()
        print("Scan this QR code with the Swoosh iOS app to pair:")
        print()

        // Generate QR code
        if let qrCode = generateQRCode(from: jsonString) {
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

    private func generateQRCode(from string: String) -> String? {
        #if canImport(CoreImage) && canImport(AppKit)
        guard let data = string.data(using: .utf8) else { return nil }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return nil }

        // Scale up for better visibility
        let scaleX = 10.0
        let scaleY = 10.0
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Convert CIImage to CGImage
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }

        // Create a bitmap context
        let width = cgImage.width
        let height = cgImage.height

        guard let bitmapContext = CGContext(data: nil,
                                            width: width,
                                            height: height,
                                            bitsPerComponent: 8,
                                            bytesPerRow: width * 4,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }

        bitmapContext.interpolationQuality = .none
        bitmapContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let pixelData = bitmapContext.data else { return nil }
        let pixels = pixelData.bindMemory(to: UInt8.self, capacity: width * height * 4)

        // Convert to ASCII art
        var asciiArt = ""
        let asciiChars = ["  ", "░░", "▒▒", "▓▓", "██"]

        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = (y * width + x) * 4
                let brightness = Int(pixels[pixelIndex])
                let charIndex = brightness * (asciiChars.count - 1) / 255
                asciiArt += asciiChars[min(charIndex, asciiChars.count - 1)]
            }
            asciiArt += "\n"
        }

        return asciiArt
        #else
        return nil
        #endif
    }

    private func getLocalIPAddress() -> String? {
        #if canImport(SystemConfiguration)
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            let interface = ptr!.pointee
            ptr = interface.ifa_next   // advance early so `continue` is safe
            // `ifa_addr` is documented to be NULL for some interface types
            // (per getifaddrs(3)). Dereferencing without a check crashes.
            guard let addrPtr = interface.ifa_addr else { continue }
            if addrPtr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name.hasPrefix("en") || name.hasPrefix("wl") {
                    var addr = addrPtr.pointee
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(&addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                    let ip = String(cString: hostname)
                    if !ip.hasPrefix("127.") && !ip.hasPrefix("169.") {
                        address = ip
                        break
                    }
                }
            }
        }

        return address
        #else
        return nil
        #endif
    }

    private func generateBearerToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        #if canImport(Security)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw CocoaError(.fileWriteUnknown)
        }
        #else
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: 0...255)
        }
        #endif
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
