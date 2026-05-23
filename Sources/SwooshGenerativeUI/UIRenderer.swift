// SwooshGenerativeUI/UIRenderer.swift — SwiftUI tree walker (0.4A)
//
// Takes a `UISurfaceUpdate` + `ComponentCatalog` + action handler and
// renders the surface in SwiftUI. The walker resolves child IDs from the
// flat component list and consults the catalog before rendering each node —
// nothing draws unless the catalog says it can.
//
// Style resolution defers to the active `SwooshTheme` from the SwooshUI
// environment when present; otherwise it uses sensible defaults.

import SwiftUI

// MARK: - Public renderer

public struct UIRenderer: View {
    public let surface: UISurfaceUpdate
    public let catalog: ComponentCatalog
    public let handler: UIActionHandler

    public init(
        surface: UISurfaceUpdate,
        catalog: ComponentCatalog = .standard,
        onAction: @escaping UIActionHandler = uiActionHandlerNoop
    ) {
        self.surface = surface
        self.catalog = catalog
        self.handler = onAction
    }

    public var body: some View {
        let issues = surface.validate(against: catalog)
        if issues.isEmpty {
            UIComponentRenderer(
                componentID: surface.rootID,
                surface: surface,
                catalog: catalog,
                handler: handler
            )
        } else {
            UIValidationErrorView(issues: issues, surface: surface)
        }
    }
}

// MARK: - Internal walker

struct UIComponentRenderer: View {
    let componentID: String
    let surface: UISurfaceUpdate
    let catalog: ComponentCatalog
    let handler: UIActionHandler

    var body: some View {
        if let component = surface.component(id: componentID),
           catalog.allows(component.body.typeName) {
            renderBody(component)
                .applyStyle(component.style)
        } else if let component = surface.component(id: componentID) {
            // Found but not in catalog — render a small placeholder so the
            // surrounding tree still lays out.
            UICatalogBlockedView(typeName: component.body.typeName)
        } else {
            // Missing reference — surface this loudly in debug, but don't
            // crash the surface.
            UIMissingComponentView(id: componentID)
        }
    }

    @ViewBuilder
    private func renderBody(_ component: UIComponent) -> some View {
        switch component.body {
        // Text
        case let .text(s):
            UITextView(text: s, style: component.style)
        case let .heading(s, level):
            UIHeadingView(text: s, level: level, style: component.style)
        case let .caption(s):
            UICaptionView(text: s)
        case let .markdown(s):
            UIMarkdownView(text: s)
        case let .code(s, language):
            UICodeView(text: s, language: language)

        // Layout
        case let .column(children, spacing, alignment):
            UIColumnView(
                children: children, spacing: spacing, alignment: alignment,
                surface: surface, catalog: catalog, handler: handler
            )
        case let .row(children, spacing, alignment):
            UIRowView(
                children: children, spacing: spacing, alignment: alignment,
                surface: surface, catalog: catalog, handler: handler
            )
        case let .grid(children, columns, spacing):
            UIGridView(
                children: children, columns: columns, spacing: spacing,
                surface: surface, catalog: catalog, handler: handler
            )
        case let .stack(children):
            UIStackView(
                children: children, surface: surface, catalog: catalog, handler: handler
            )
        case let .spacer(minLength):
            Spacer(minLength: minLength.map { CGFloat($0) })
        case .divider:
            Divider()

        // Containers
        case let .card(child, title, subtitle):
            UICardView(
                child: child, title: title, subtitle: subtitle,
                surface: surface, catalog: catalog, handler: handler
            )
        case let .glassPanel(child):
            UIGlassPanelView(
                child: child, surface: surface, catalog: catalog, handler: handler
            )
        case let .section(child, header, footer):
            UISectionView(
                child: child, header: header, footer: footer,
                surface: surface, catalog: catalog, handler: handler
            )
        case let .scrollContainer(child, axis):
            UIScrollContainerView(
                child: child, axis: axis,
                surface: surface, catalog: catalog, handler: handler
            )

        // Indicators
        case let .statusChip(label, tint, systemImage):
            UIStatusChipView(label: label, tint: tint, systemImage: systemImage)
        case let .badge(label, count, tint):
            UIBadgeView(label: label, count: count, tint: tint)
        case let .progress(value, label):
            UIProgressView(value: value, label: label)
        case let .meter(value, range, label):
            UIMeterView(value: value, range: range, label: label)
        case .loadingDots:
            UILoadingDotsView()

        // Media
        case let .image(systemName, url, size):
            UIImageView(systemName: systemName, url: url, size: size)
        case let .avatar(systemName, url, label):
            UIAvatarView(systemName: systemName, url: url, label: label)

        // Interaction
        case let .button(label, action, systemImage, style):
            UIButtonView(
                label: label, action: action, systemImage: systemImage, style: style,
                componentID: component.id, surfaceID: surface.surfaceID, handler: handler,
                catalog: catalog
            )
        case let .link(label, url):
            UILinkView(label: label, url: url)
        case let .toggle(label, isOn, action):
            UIToggleView(
                label: label, isOn: isOn, action: action,
                componentID: component.id, surfaceID: surface.surfaceID, handler: handler,
                catalog: catalog
            )

        // Data
        case let .list(items, style):
            UIListView(
                items: items, style: style,
                surface: surface, catalog: catalog, handler: handler
            )
        case let .chart(series, kind, title):
            UIChartView(series: series, kind: kind, title: title)
        case let .keyValue(pairs):
            UIKeyValueView(pairs: pairs)
        case let .table(columns, rows):
            UITableView(columns: columns, rows: rows)
        }
    }
}
