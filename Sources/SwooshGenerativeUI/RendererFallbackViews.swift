// SwooshGenerativeUI/RendererFallbackViews.swift — Renderer validation fallback views (0.4A)

import SwiftUI

struct UIValidationErrorView: View {
    let issues: [UISurfaceUpdate.ValidationIssue]
    let surface: UISurfaceUpdate

    var body: some View {
        VStack(alignment: .leading, spacing: SwooshNeonTokens.Spacing.micro) {
            HStack(spacing: SwooshNeonTokens.Spacing.micro) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(SwooshNeonTokens.Accent.gold)
                Text("Surface \(surface.surfaceID) failed validation")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
            }
            ForEach(0..<issues.count, id: \.self) { idx in
                Text("• \(describe(issues[idx]))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text2)
            }
        }
        .padding(SwooshNeonTokens.Spacing.base + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neonTile(.gold, state: .focus, shape: .card)
    }

    private func describe(_ issue: UISurfaceUpdate.ValidationIssue) -> String {
        switch issue {
        case let .rootMissing(id):
            return "Root component '\(id)' missing"
        case let .duplicateID(id):
            return "Duplicate component id '\(id)'"
        case let .childMissing(parent, missing):
            return "'\(parent)' references missing child '\(missing)'"
        case let .typeNotInCatalog(component, type):
            return "'\(component)' uses type '\(type)' not in catalog"
        }
    }
}

struct UICatalogBlockedView: View {
    let typeName: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 10))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            Text("Blocked: \(typeName)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
        }
        .padding(.horizontal, SwooshNeonTokens.Spacing.micro)
        .padding(.vertical, 3)
        .neonTile(.cyan, state: .idle, shape: .card)
    }
}

struct UIMissingComponentView: View {
    let id: String

    var body: some View {
        Text("Missing: \(id)")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(SwooshNeonTokens.Accent.gold)
            .padding(.horizontal, SwooshNeonTokens.Spacing.micro)
            .padding(.vertical, 3)
            .neonTile(.gold, state: .focus, shape: .card)
    }
}
