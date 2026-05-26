// DetourCanvasArtifactModels.swift — canvas artifact sidecar models (0.5A)

import Foundation

enum DetourCanvasArtifactKind: String, CaseIterable {
    case brief
    case workspace
    case runbook
    case template
    case preview

    var title: String {
        switch self {
        case .brief: "Brief"
        case .workspace: "Workspace"
        case .runbook: "Runbook"
        case .template: "Template"
        case .preview: "Preview"
        }
    }

    var systemImage: String {
        switch self {
        case .brief: "doc.text"
        case .workspace: "rectangle.3.group"
        case .runbook: "checklist"
        case .template: "curlybraces"
        case .preview: "play.rectangle"
        }
    }
}

struct DetourCanvasArtifact: Identifiable, Equatable {
    var id: String
    var title: String
    var subtitle: String
    var kind: DetourCanvasArtifactKind
    var status: DetourCanvasStatus
    var markdown: String
}
