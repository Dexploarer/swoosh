// DetourSetupInsightCopy.swift — setup insight plain-language copy (0.5A)

import Foundation

enum DetourSetupInsightCopy {
    static func sectionDetail(_ category: DetourSetupInsightCategory) -> String {
        switch category {
        case .setupChecks:
            "What Detour has already saved, tested, or still needs."
        case .accounts:
            "Accounts Detour can understand from your perspective."
        case .credentials:
            "Saved access Detour can use only after you approve scope."
        case .connectors:
            "Apps and services Detour can connect through real runtime checks."
        case .mcpServers:
            "Tool servers Detour can register and keep approval-gated."
        case .permissions:
            "Mac permissions needed before Detour can use local context."
        case .relationships:
            "People Detour should understand with your guidance."
        case .providers:
            "Model providers and local runtimes Detour can route through."
        case .goalsSchedules:
            "Goals and routines Detour can keep in view."
        case .appActivitySignals:
            "Local usage signals summarized without raw history."
        case .capabilitySummary:
            "What Detour can use after setup finishes."
        }
    }
}
