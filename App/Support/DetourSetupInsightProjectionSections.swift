// DetourSetupInsightProjectionSections.swift — setup insight section merging (0.5A)

import Foundation

extension DetourSetupInsightProjection {
    static func mergedSections(_ sections: [DetourSetupInsightSection]) -> [DetourSetupInsightSection] {
        var byID: [String: DetourSetupInsightSection] = [:]
        var order: [String] = []
        for section in sections where !section.items.isEmpty {
            if var existing = byID[section.id] {
                existing.items.append(contentsOf: section.items)
                byID[section.id] = existing
            } else {
                byID[section.id] = section
                order.append(section.id)
            }
        }
        return order.compactMap { id in
            guard var section = byID[id] else { return nil }
            section.items = uniqueItems(section.items)
            return section
        }
    }

    private static func uniqueItems(_ items: [DetourSetupInsightItem]) -> [DetourSetupInsightItem] {
        var seen: Set<String> = []
        return items.filter { item in
            let key = [
                item.id,
                item.title.lowercased(),
                item.detail.lowercased(),
                item.owner.rawValue,
            ].joined(separator: "|")
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }
}
