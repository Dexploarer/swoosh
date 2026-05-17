// SwooshFlow/WorkflowExporter.swift — Export drafts as JSON/YAML/Markdown (0.5A)

import Foundation

public enum WorkflowExportFormat: String, Codable, Sendable {
    case json, yaml, markdown
}

public struct WorkflowExporter: Sendable {
    public init() {}

    public func export(_ draft: WorkflowDraft05A, format: WorkflowExportFormat) throws -> String {
        switch format {
        case .json: return try exportJSON(draft)
        case .yaml: return exportYAML(draft)
        case .markdown: return exportMarkdown(draft)
        }
    }

    private func exportJSON(_ draft: WorkflowDraft05A) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(draft)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func exportYAML(_ draft: WorkflowDraft05A) -> String {
        var lines: [String] = []
        lines.append("id: \(draft.id)")
        lines.append("name: \(draft.name)")
        lines.append("summary: \(draft.summary)")
        lines.append("status: \(draft.status.rawValue)")
        lines.append("trigger:")
        switch draft.trigger {
        case .manual: lines.append("  type: manual")
        case .placeholder(let p):
            lines.append("  type: placeholder")
            lines.append("  kind: \(p.kind.rawValue)")
            lines.append("  description: \(p.humanDescription)")
        }
        lines.append("risk: \(draft.risk.rawValue)")
        if !draft.variables.isEmpty {
            lines.append("variables:")
            for v in draft.variables {
                lines.append("  - name: \(v.name)")
                lines.append("    type: \(v.type.rawValue)")
                lines.append("    required: \(v.required)")
                lines.append("    description: \(v.description)")
            }
        }
        if !draft.requiredPermissions.isEmpty {
            lines.append("requiredPermissions:")
            for p in draft.requiredPermissions {
                lines.append("  - \(p.permission.rawValue)")
            }
        }
        lines.append("steps:")
        for step in draft.steps {
            lines.append("  - id: \(step.id)")
            lines.append("    index: \(step.index)")
            lines.append("    title: \(step.title)")
            lines.append("    kind: \(step.kind.rawValue)")
            if let tool = step.toolName { lines.append("    toolName: \(tool)") }
            if step.risk != .readOnly { lines.append("    risk: \(step.risk.rawValue)") }
            if step.approval != .never { lines.append("    approval: \(step.approval)") }
        }
        lines.append("provenance:")
        lines.append("  sourceSessionID: \(draft.provenance.sourceSessionID)")
        lines.append("  sourceToolTraceIDs: [\(draft.provenance.sourceToolTraceIDs.joined(separator: ", "))]")
        return lines.joined(separator: "\n")
    }

    private func exportMarkdown(_ draft: WorkflowDraft05A) -> String {
        var md = "# \(draft.name)\n\n"
        md += "> \(draft.summary)\n\n"
        md += "**Status:** \(draft.status.rawValue)  \n"
        md += "**Trigger:** \(triggerDescription(draft.trigger))  \n"
        md += "**Risk:** \(draft.risk.rawValue)  \n\n"
        if !draft.variables.isEmpty {
            md += "## Variables\n\n"
            for v in draft.variables {
                md += "- **\(v.name)** (\(v.type.rawValue)): \(v.description)\n"
            }
            md += "\n"
        }
        md += "## Steps\n\n"
        for step in draft.steps {
            let icon: String
            switch step.kind {
            case .toolCall: icon = "🔧"
            case .modelSummarize: icon = "🤖"
            case .humanReview: icon = "👤"
            case .approvalGate: icon = "🔒"
            case .note: icon = "📝"
            case .unsupported: icon = "⚠️"
            }
            md += "\(step.index). \(icon) **\(step.title)**"
            if let tool = step.toolName { md += " (`\(tool)`)" }
            if step.risk != .readOnly { md += " — risk: \(step.risk.rawValue)" }
            md += "\n"
        }
        if !draft.requiredPermissions.isEmpty {
            md += "\n## Required Permissions\n\n"
            for p in draft.requiredPermissions { md += "- `\(p.permission.rawValue)`: \(p.reason)\n" }
        }
        md += "\n---\n*Generated from session \(draft.provenance.sourceSessionID)*\n"
        return md
    }

    private func triggerDescription(_ trigger: WorkflowTrigger05A) -> String {
        switch trigger {
        case .manual: return "Manual only"
        case .placeholder(let p): return "\(p.humanDescription) (placeholder — manual only until 0.6A)"
        }
    }
}
