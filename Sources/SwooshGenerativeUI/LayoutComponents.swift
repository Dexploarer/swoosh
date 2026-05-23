// SwooshGenerativeUI/LayoutComponents.swift — Built-in layout component views (0.4A)

import SwiftUI

struct UIColumnView: View {
    let children: [String]
    let spacing: Double?
    let alignment: String?
    let surface: UISurfaceUpdate
    let catalog: ComponentCatalog
    let handler: UIActionHandler

    var body: some View {
        VStack(alignment: resolveHAlignment(alignment), spacing: CGFloat(spacing ?? 8)) {
            ForEach(children, id: \.self) { id in
                UIComponentRenderer(componentID: id, surface: surface, catalog: catalog, handler: handler)
            }
        }
    }
}

struct UIRowView: View {
    let children: [String]
    let spacing: Double?
    let alignment: String?
    let surface: UISurfaceUpdate
    let catalog: ComponentCatalog
    let handler: UIActionHandler

    var body: some View {
        HStack(alignment: resolveVAlignment(alignment), spacing: CGFloat(spacing ?? 8)) {
            ForEach(children, id: \.self) { id in
                UIComponentRenderer(componentID: id, surface: surface, catalog: catalog, handler: handler)
            }
        }
    }
}

struct UIGridView: View {
    let children: [String]
    let columns: Int
    let spacing: Double?
    let surface: UISurfaceUpdate
    let catalog: ComponentCatalog
    let handler: UIActionHandler

    var body: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: CGFloat(spacing ?? 8)), count: max(1, columns))
        LazyVGrid(columns: cols, spacing: CGFloat(spacing ?? 8)) {
            ForEach(children, id: \.self) { id in
                UIComponentRenderer(componentID: id, surface: surface, catalog: catalog, handler: handler)
            }
        }
    }
}

struct UIStackView: View {
    let children: [String]
    let surface: UISurfaceUpdate
    let catalog: ComponentCatalog
    let handler: UIActionHandler

    var body: some View {
        ZStack {
            ForEach(children, id: \.self) { id in
                UIComponentRenderer(componentID: id, surface: surface, catalog: catalog, handler: handler)
            }
        }
    }
}

func resolveHAlignment(_ token: String?) -> HorizontalAlignment {
    switch token {
    case "center": return .center
    case "trailing": return .trailing
    default: return .leading
    }
}

func resolveVAlignment(_ token: String?) -> VerticalAlignment {
    switch token {
    case "top": return .top
    case "bottom": return .bottom
    case "firstTextBaseline": return .firstTextBaseline
    default: return .center
    }
}
