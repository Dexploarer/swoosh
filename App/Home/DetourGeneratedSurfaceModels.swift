// DetourGeneratedSurfaceModels.swift — safe generated home surface schema (0.5A)

import Foundation

struct DetourGeneratedSurface {
    var rootID: String
    var components: [DetourGeneratedComponent]

    func component(id: String) -> DetourGeneratedComponent? {
        components.first { $0.id == id }
    }
}

struct DetourGeneratedComponent: Identifiable {
    var id: String
    var body: DetourGeneratedComponentBody
}

enum DetourGeneratedComponentBody {
    case column(children: [String], spacing: Double)
    case row(children: [String], spacing: Double)
    case grid(children: [String], minimumWidth: Double)
    case panel(child: String, tone: DetourGeneratedTone)
    case heading(title: String, subtitle: String?)
    case hero(agentName: String, summary: String, workspace: String)
    case metric(title: String, value: String, detail: String, tone: DetourGeneratedTone)
    case status(label: String, tone: DetourGeneratedTone)
    case button(title: String, systemImage: String, action: DetourGeneratedAction, prominent: Bool)
    case chips(title: String, subtitle: String?, chips: [DetourGeneratedChip], overflow: Int)
    case socialConnector(DetourGeneratedConnector)
    case nativePanel(DetourGeneratedNativePanel)
    case setupItem(DetourSetupInsightItem)
    case inboxItem(DetourHomeInboxItem)
    case message(title: String, detail: String, tone: DetourGeneratedTone)
}

enum DetourGeneratedNativePanel {
    case apps
    case socialOnChain
    case universalInbox
    case settings
}

enum DetourGeneratedTone {
    case accent
    case blue
    case green
    case indigo
    case orange
    case secondary
}

enum DetourGeneratedAction {
    case reviewSetup
    case applySetup
    case refreshWallet
    case refreshInbox
    case setupInsight(DetourSetupInsightAction)
}

struct DetourGeneratedChip: Identifiable, Equatable {
    var id: String
    var title: String
    var tone: DetourGeneratedTone

    init(id: String? = nil, title: String, tone: DetourGeneratedTone) {
        self.id = id ?? title
        self.title = title
        self.tone = tone
    }
}

struct DetourGeneratedConnector: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var status: String
    var detail: String
    var systemImage: String
    var tone: DetourGeneratedTone
    var ready: Bool
}
