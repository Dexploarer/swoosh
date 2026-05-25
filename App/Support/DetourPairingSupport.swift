// DetourPairingSupport.swift — local daemon pairing payload and QR image support (0.5A)

import AppKit
import CoreImage
import Darwin
import Foundation
import Security

enum DetourDeviceKind: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case macBook
    case macMini
    case iMac
    case macStudio
    case iPhone
    case iPad
    case appleWatch
    case visionPro
    case remoteDetour

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .macBook:
            "MacBook"
        case .macMini:
            "Mac mini"
        case .remoteDetour:
            "Remote Detour"
        case .iPhone:
            "iPhone"
        case .iPad:
            "iPad"
        case .appleWatch:
            "Apple Watch"
        case .iMac:
            "iMac"
        case .macStudio:
            "Mac Studio"
        case .visionPro:
            "Apple Vision Pro"
        }
    }

    var symbolNames: [String] {
        switch self {
        case .macBook:
            ["macbook", "laptopcomputer"]
        case .macMini:
            ["macmini", "desktopcomputer"]
        case .remoteDetour:
            ["server.rack", "network"]
        case .iPhone:
            ["iphone"]
        case .iPad:
            ["ipad"]
        case .appleWatch:
            ["applewatch"]
        case .iMac:
            ["desktopcomputer"]
        case .macStudio:
            ["macstudio", "macmini", "desktopcomputer"]
        case .visionPro:
            ["visionpro", "goggles", "eye"]
        }
    }

    var symbolImage: NSImage? {
        for name in symbolNames {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: displayName) {
                return image
            }
        }

        return nil
    }
}

struct DetourRemoteInstance: Codable, Equatable, Hashable {
    var host: String
    var sshUser: String
    var sshPort: Int

    init(host: String, sshUser: String, sshPort: Int = 22) {
        self.host = host
        self.sshUser = sshUser
        self.sshPort = sshPort
    }
}

struct DetourPairingInfo: Equatable {
    let host: String
    let token: String
    let payload: String
    let deepLinkPayload: String
    let requiredIOSAppVersion: String
    let qrImage: NSImage

    static func == (left: DetourPairingInfo, right: DetourPairingInfo) -> Bool {
        left.host == right.host && left.token == right.token && left.payload == right.payload
    }
}

enum DetourPairingSupport {
    static let iOSBundleIdentifier = "ai.swoosh.app.ios"
    static let requiredIOSAppVersion = "0.5"

    static func pairingInfo(port: Int = 8787) throws -> DetourPairingInfo {
        let token = try ensureBearerToken()
        let ipAddress = localIPAddress() ?? "127.0.0.1"
        let host = "http://\(ipAddress):\(port)"
        let deepLink = try deepLinkPairingPayload(host: host, token: token)
        let payload = try DetourPairingWebServer.shared
            .pairingPageURL(ipAddress: ipAddress, daemonHost: host, token: token)
            .absoluteString
        guard let image = qrImage(from: payload) else {
            throw DetourPairingError.qrGenerationFailed
        }

        return DetourPairingInfo(
            host: host,
            token: token,
            payload: payload,
            deepLinkPayload: deepLink,
            requiredIOSAppVersion: requiredIOSAppVersion,
            qrImage: image
        )
    }

    static func ensureBearerToken() throws -> String {
        let tokenFile = apiTokenFile()
        if let existing = try? String(contentsOf: tokenFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            return existing
        }

        try FileManager.default.createDirectory(
            at: tokenFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let token = try mintToken()
        try Data(token.utf8).write(to: tokenFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenFile.path)
        return token
    }

    private static func apiTokenFile() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swoosh", isDirectory: true)
            .appendingPathComponent("api_token", isDirectory: false)
    }

    private static func mintToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw DetourPairingError.tokenGenerationFailed(status)
        }

        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func deepLinkPairingPayload(host: String, token: String) throws -> String {
        var components = URLComponents()
        components.scheme = "swoosh"
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "host", value: host),
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "app", value: iOSBundleIdentifier),
            URLQueryItem(name: "min_ios_version", value: requiredIOSAppVersion)
        ]

        guard let string = components.url?.absoluteString else {
            throw DetourPairingError.payloadEncodingFailed
        }
        return string
    }

    private static func qrImage(from payload: String) -> NSImage? {
        guard let data = payload.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }

        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }

        let image = NSImage(size: scaled.extent.size)
        image.addRepresentation(NSBitmapImageRep(cgImage: cgImage))
        return image
    }

    private static func localIPAddress() -> String? {
        var candidates: [(name: String, ip: String)] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var cursor = ifaddr
        while let currentPointer = cursor {
            let interface = currentPointer.pointee
            cursor = interface.ifa_next
            guard let addressPointer = interface.ifa_addr else { continue }
            guard addressPointer.pointee.sa_family == UInt8(AF_INET) else { continue }
            guard interface.ifa_flags & UInt32(IFF_UP) != 0,
                  interface.ifa_flags & UInt32(IFF_RUNNING) != 0 else { continue }
            let name = String(cString: interface.ifa_name)
            guard isInterestingInterface(name) else { continue }

            var socketAddress = addressPointer.pointee
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                &socketAddress,
                socklen_t(socketAddress.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            let ip = hostname.withUnsafeBufferPointer { buffer -> String in
                var bytes: [UInt8] = []
                for character in buffer {
                    guard character != 0 else { break }
                    bytes.append(UInt8(bitPattern: character))
                }
                return String(decoding: bytes, as: UTF8.self)
            }
            guard !ip.hasPrefix("127.") && !ip.hasPrefix("169.") else { continue }
            candidates.append((name: name, ip: ip))
        }

        return candidates.first(where: { $0.name == "en0" })?.ip
            ?? candidates.first(where: { $0.name.hasPrefix("en") })?.ip
            ?? candidates.first?.ip
    }

    private static func isInterestingInterface(_ name: String) -> Bool {
        ["en", "eth", "wl", "wlan"].contains { name.hasPrefix($0) }
    }
}

enum DetourPairingError: LocalizedError {
    case tokenGenerationFailed(OSStatus)
    case payloadEncodingFailed
    case qrGenerationFailed
    case pairingServerFailed

    var errorDescription: String? {
        switch self {
        case .tokenGenerationFailed(let status):
            "Could not generate a daemon token: \(status)."
        case .payloadEncodingFailed:
            "Could not encode the daemon pairing payload."
        case .qrGenerationFailed:
            "Could not generate the daemon pairing QR code."
        case .pairingServerFailed:
            "Could not start the local pairing page."
        }
    }
}
