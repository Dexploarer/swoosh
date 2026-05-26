// OnboardingStoreCollectionExtensions.swift — collection helpers for onboarding state (0.5A)

import Foundation


extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Array where Element == DetourDiscoveredDevice {
    func uniquedByKindAndName() -> [DetourDiscoveredDevice] {
        var seen = Set<String>()
        return filter { device in
            let key = "\(device.kind.rawValue):\(device.name)"
            return seen.insert(key).inserted
        }
    }
}
