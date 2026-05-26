// DetourDeviceDiscovery.swift — local Apple-device discovery for onboarding (0.5A)

import Foundation
@preconcurrency import Network

struct DetourDiscoveredDevice: Equatable, Hashable, Identifiable, Sendable {
    let kind: DetourDeviceKind
    let name: String
    let source: String

    var id: String {
        "\(source):\(kind.rawValue):\(name)"
    }
}

actor DetourDeviceDiscovery {
    func discover() async -> [DetourDiscoveredDevice] {
        async let bonjour = Self.scanBonjour()
        async let usb = Self.scanSystemProfiler(dataType: "SPUSBDataType", source: "usb")
        async let bluetooth = Self.scanSystemProfiler(dataType: "SPBluetoothDataType", source: "bluetooth")
        return Self.unique((await bonjour) + (await usb) + (await bluetooth))
    }

    private static func scanBonjour(timeout: TimeInterval = 2) async -> [DetourDiscoveredDevice] {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "ai.swoosh.detour.discovery.bonjour")
            let browser = NWBrowser(
                for: .bonjour(type: "_swoosh._tcp", domain: nil),
                using: .tcp
            )
            let box = BonjourResults()
            browser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    if case .service(let name, _, _, _) = result.endpoint {
                        box.insert(DetourDiscoveredDevice(kind: .remoteDetour, name: name, source: "bonjour"))
                    }
                }
            }
            browser.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                browser.cancel()
                continuation.resume(returning: box.values())
            }
        }
    }

    private static func scanSystemProfiler(dataType: String, source: String) async -> [DetourDiscoveredDevice] {
        await Task.detached(priority: .utility) {
            do {
                let data = try runSystemProfiler(dataType: dataType)
                let object = try JSONSerialization.jsonObject(with: data)
                return discoveredDevices(in: object, source: source)
            } catch {
                return []
            }
        }.value
    }

    private static func runSystemProfiler(dataType: String) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = [dataType, "-json", "-detailLevel", "mini"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()

        let deadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()
        return output.fileHandleForReading.readDataToEndOfFile()
    }

    private static func discoveredDevices(in value: Any, source: String) -> [DetourDiscoveredDevice] {
        var devices: [DetourDiscoveredDevice] = []

        func visit(_ value: Any, inheritedName: String?) {
            if let dictionary = value as? [String: Any] {
                let payload = ([inheritedName].compactMap { $0 } + flattenedStrings(in: dictionary)).joined(separator: " ")
                if let kind = deviceKind(in: payload) {
                    let name = deviceName(in: dictionary, inheritedName: inheritedName, kind: kind)
                    devices.append(DetourDiscoveredDevice(kind: kind, name: name, source: source))
                }

                for (key, child) in dictionary {
                    visit(child, inheritedName: key)
                }
                return
            }

            if let array = value as? [Any] {
                for child in array {
                    visit(child, inheritedName: inheritedName)
                }
                return
            }

            if let string = value as? String,
               let kind = deviceKind(in: [inheritedName, string].compactMap({ $0 }).joined(separator: " ")) {
                devices.append(
                    DetourDiscoveredDevice(
                        kind: kind,
                        name: inheritedName ?? kind.displayName,
                        source: source
                    )
                )
            }
        }

        visit(value, inheritedName: nil)
        return unique(devices)
    }

    private static func flattenedStrings(in value: Any) -> [String] {
        if let dictionary = value as? [String: Any] {
            return dictionary.flatMap { key, child in
                [key] + flattenedStrings(in: child)
            }
        }
        if let array = value as? [Any] {
            return array.flatMap(flattenedStrings)
        }
        if let string = value as? String {
            return [string]
        }
        return []
    }

    private static func deviceName(
        in dictionary: [String: Any],
        inheritedName: String?,
        kind: DetourDeviceKind
    ) -> String {
        let keys = ["_name", "device_name", "name", "product_name"]
        for key in keys {
            if let value = dictionary[key] as? String,
               deviceKind(in: value) == kind {
                return value
            }
        }

        if let inheritedName,
           deviceKind(in: inheritedName) == kind {
            return inheritedName
        }

        return kind.displayName
    }

    private static func deviceKind(in text: String) -> DetourDeviceKind? {
        let value = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        if value.contains("iphone") { return .iPhone }
        if value.contains("ipad") { return .iPad }
        if value.contains("apple watch") { return .appleWatch }
        if value.contains("vision pro") || value.contains("visionpro") { return .visionPro }
        if value.contains("macbook") || value.contains("mac book") { return .macBook }
        if value.contains("mac mini") || value.contains("macmini") { return .macMini }
        if value.contains("imac") { return .iMac }
        if value.contains("mac studio") || value.contains("macstudio") { return .macStudio }
        if value.contains("remote detour") { return .remoteDetour }
        return nil
    }

    private static func unique(_ devices: [DetourDiscoveredDevice]) -> [DetourDiscoveredDevice] {
        var seen = Set<String>()
        return devices
            .filter { device in
                let key = "\(device.kind.rawValue):\(device.name)"
                return seen.insert(key).inserted
            }
            .sorted { left, right in
                if left.kind.rawValue == right.kind.rawValue {
                    return left.name.localizedStandardCompare(right.name) == .orderedAscending
                }
                return left.kind.displayName.localizedStandardCompare(right.kind.displayName) == .orderedAscending
            }
    }
}

private final class BonjourResults: @unchecked Sendable {
    private let lock = NSLock()
    private var devices: [DetourDiscoveredDevice] = []

    func insert(_ device: DetourDiscoveredDevice) {
        lock.lock(); defer { lock.unlock() }
        devices.append(device)
    }

    func values() -> [DetourDiscoveredDevice] {
        lock.lock(); defer { lock.unlock() }
        return devices
    }
}
