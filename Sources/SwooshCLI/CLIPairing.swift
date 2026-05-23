// SwooshCLI/CLIPairing.swift — QR + local-IP helpers for daemon pairing — 0.4B
//
// Pulled out of DaemonPairCommand so the menu-bar app can reuse the same
// QR + IP discovery when it grows its own pairing surface, and so the
// CLI command file stays a thin dispatch shell.
//
// 0.4B revision: no force unwraps in the `getifaddrs` walk; QR pixels
// rendered at 1× (terminal-sized) instead of 10× (off-screen); interface
// name match expanded to include Linux `eth*` / `wlan*` prefixes.

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

enum CLIPairing {
    /// Render `string` as an ASCII-art QR code, or `nil` when CoreImage
    /// is unavailable (Linux CI). Pixels are rendered at 1× so the result
    /// fits inside a typical 80-column terminal — QR codes are usually
    /// 25–45 modules per side and a 2-char ASCII cell keeps the aspect
    /// ratio readable. Earlier revisions used a 10× scale which produced
    /// output too wide to scan from a terminal.
    static func generateQRCode(from string: String) -> String? {
        #if canImport(CoreImage) && canImport(AppKit)
        guard let data = string.data(using: .utf8) else { return nil }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return nil }

        let context = CIContext()
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else { return nil }

        let width = cgImage.width
        let height = cgImage.height

        guard let bitmapContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        bitmapContext.interpolationQuality = .none
        bitmapContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let pixelData = bitmapContext.data else { return nil }
        let pixels = pixelData.bindMemory(to: UInt8.self, capacity: width * height * 4)

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

    /// Walk `getifaddrs` for an IPv4 address on a Wi-Fi/Ethernet
    /// interface, skipping loopback and link-local ranges. Returns `nil`
    /// when no usable interface is available (Linux, locked-down CI).
    static func localIPAddress() -> String? {
        #if canImport(SystemConfiguration)
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var cursor = ifaddr
        while let currentPtr = cursor {
            let interface = currentPtr.pointee
            cursor = interface.ifa_next   // advance early so `continue` is safe
            // `ifa_addr` is documented to be NULL for some interface types
            // (per getifaddrs(3)). Dereferencing without a check crashes.
            guard let addrPtr = interface.ifa_addr else { continue }
            guard addrPtr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard Self.isInterestingInterface(name) else { continue }
            var addr = addrPtr.pointee
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(&addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
            guard let ip = hostname.withUnsafeBufferPointer({ buf -> String? in
                guard let base = buf.baseAddress else { return nil }
                return String(cString: base)
            }) else { continue }
            if !ip.hasPrefix("127.") && !ip.hasPrefix("169.") {
                address = ip
                break
            }
        }

        return address
        #else
        return nil
        #endif
    }

    /// JSON blob that the iOS app's QR scanner expects. Exposed so tests
    /// can verify the wire shape without re-rendering the QR pixels.
    static func pairingPayload(host: String, token: String) -> String? {
        let payload: [String: String] = ["host": host, "token": token]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Interface name match for `localIPAddress`. macOS uses `en*`,
    /// Linux uses `eth*` / `wlan*` / `wl*`, FreeBSD wireless uses `wlan*`.
    /// Loopback / docker / utun / bridge / etc. are intentionally excluded.
    static func isInterestingInterface(_ name: String) -> Bool {
        let prefixes = ["en", "eth", "wl", "wlan"]
        return prefixes.contains(where: { name.hasPrefix($0) })
    }
}
