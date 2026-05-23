// SwooshGenerativeUI/ContainerComponents.swift — Built-in container component views (0.4A)

import SwiftUI

struct UICardView: View {
    let child: String
    let title: String?
    let subtitle: String?
    let surface: UISurfaceUpdate
    let catalog: ComponentCatalog
    let handler: UIActionHandler

    var body: some View {
        VStack(alignment: .leading, spacing: SwooshNeonTokens.Spacing.base) {
            if let title {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text2)
            }
            UIComponentRenderer(componentID: child, surface: surface, catalog: catalog, handler: handler)
        }
        .padding(SwooshNeonTokens.Spacing.base + 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neonTile(.cyan, state: .idle, shape: .card)
    }
}

struct UIGlassPanelView: View {
    let child: String
    let surface: UISurfaceUpdate
    let catalog: ComponentCatalog
    let handler: UIActionHandler

    var body: some View {
        UIComponentRenderer(componentID: child, surface: surface, catalog: catalog, handler: handler)
            .padding(14)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct UISectionView: View {
    let child: String
    let header: String?
    let footer: String?
    let surface: UISurfaceUpdate
    let catalog: ComponentCatalog
    let handler: UIActionHandler

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header {
                Text(header)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            UIComponentRenderer(componentID: child, surface: surface, catalog: catalog, handler: handler)
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct UIScrollContainerView: View {
    let child: String
    let axis: String?
    let surface: UISurfaceUpdate
    let catalog: ComponentCatalog
    let handler: UIActionHandler

    var body: some View {
        ScrollView(axis?.lowercased() == "horizontal" ? .horizontal : .vertical, showsIndicators: false) {
            UIComponentRenderer(componentID: child, surface: surface, catalog: catalog, handler: handler)
                .padding(2)
        }
    }
}
