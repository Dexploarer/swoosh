// SwooshGenerativeUI/Builtins.swift — Per-component SwiftUI views (0.4A)
//
// One view per built-in component body. Each view reads the active theme
// from the `SwooshUI` environment (if present) and applies semantic tints,
// typography, and corner radii through that theme — agents emit tokens like
// "accent" / "success", not raw colors.

import SwiftUI
#if canImport(Charts)
import Charts
#endif

// MARK: - Tint resolution

/// Translate a semantic-or-hex string into a SwiftUI `Color`. Falls back to
/// `.accentColor` for unknown tokens.
@MainActor
func resolveTint(_ token: String?) -> Color {
    guard let token = token else { return .accentColor }
    switch token.lowercased() {
    case "accent":    return .accentColor
    case "primary":   return .primary
    case "secondary": return .secondary
    case "success":   return .green
    case "warning":   return .yellow
    case "error":     return .red
    case "info":      return .blue
    default:
        if token.hasPrefix("#") { return hexColor(token) }
        return .accentColor
    }
}

func hexColor(_ hex: String) -> Color {
    let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "#", with: "")
    var int: UInt64 = 0
    Scanner(string: cleaned).scanHexInt64(&int)
    let r, g, b: UInt64
    switch cleaned.count {
    case 6:
        r = int >> 16
        g = int >> 8 & 0xFF
        b = int & 0xFF
    case 3:
        r = (int >> 8) * 17
        g = (int >> 4 & 0xF) * 17
        b = (int & 0xF) * 17
    default:
        return .accentColor
    }
    return Color(.sRGB,
                 red: Double(r) / 255.0,
                 green: Double(g) / 255.0,
                 blue: Double(b) / 255.0,
                 opacity: 1)
}

@MainActor
func resolveFontDesign(_ token: String?) -> Font.Design {
    switch token {
    case "rounded":    return .rounded
    case "serif":      return .serif
    case "monospaced": return .monospaced
    default:           return .default
    }
}

@MainActor
func resolveFontWeight(_ token: String?) -> Font.Weight {
    switch token {
    case "medium":    return .medium
    case "semibold":  return .semibold
    case "bold":      return .bold
    case "heavy":     return .heavy
    case "light":     return .light
    default:          return .regular
    }
}

// MARK: - Text family

struct UITextView: View {
    let text: String
    let style: UIStyle?

    var body: some View {
        Text(text)
            .font(.system(
                size: CGFloat(style?.fontSize ?? 14),
                weight: resolveFontWeight(style?.fontWeight),
                design: resolveFontDesign(style?.fontDesign)
            ))
            .foregroundStyle(resolveTint(style?.foreground ?? "primary"))
    }
}

struct UIHeadingView: View {
    let text: String
    let level: Int
    let style: UIStyle?

    var body: some View {
        let size: CGFloat = {
            switch level {
            case 1:  return 28
            case 2:  return 22
            case 3:  return 18
            default: return 16
            }
        }()
        Text(text)
            .font(.system(
                size: CGFloat(style?.fontSize ?? Double(size)),
                weight: .bold,
                design: resolveFontDesign(style?.fontDesign)
            ))
            .foregroundStyle(.primary)
    }
}

struct UICaptionView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct UIMarkdownView: View {
    let text: String
    var body: some View {
        // SwiftUI's `Text` supports Markdown via the LocalizedStringKey initializer.
        Text(.init(text))
            .font(.system(size: 14))
    }
}

struct UICodeView: View {
    let text: String
    let language: String?
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(10)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Layout

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
    case "center":  return .center
    case "trailing": return .trailing
    default:        return .leading
    }
}

func resolveVAlignment(_ token: String?) -> VerticalAlignment {
    switch token {
    case "top":     return .top
    case "bottom":  return .bottom
    case "firstTextBaseline": return .firstTextBaseline
    default:        return .center
    }
}

// MARK: - Containers

struct UICardView: View {
    let child: String
    let title: String?
    let subtitle: String?
    let surface: UISurfaceUpdate
    let catalog: ComponentCatalog
    let handler: UIActionHandler

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            UIComponentRenderer(componentID: child, surface: surface, catalog: catalog, handler: handler)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

// MARK: - Indicators

struct UIStatusChipView: View {
    let label: String
    let tint: String
    let systemImage: String?

    var body: some View {
        let color = resolveTint(tint)
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.16)))
    }
}

struct UIBadgeView: View {
    let label: String
    let count: Int?
    let tint: String?

    var body: some View {
        let color = resolveTint(tint ?? "accent")
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
            if let count {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(color))
            }
        }
    }
}

struct UIProgressView: View {
    let value: Double
    let label: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SwiftUI.ProgressView(value: max(0, min(1, value)))
                .progressViewStyle(.linear)
        }
    }
}

struct UIMeterView: View {
    let value: Double
    let range: ClosedRangePair
    let label: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Gauge(value: value, in: range.lower...range.upper) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinearCapacity)
        }
    }
}

struct UILoadingDotsView: View {
    @State private var phase = 0.0
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .opacity(0.3 + 0.7 * abs(sin(phase + Double(i) * 0.6)))
            }
        }
        .frame(width: 28, height: 12)
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

// MARK: - Media

struct UIImageView: View {
    let systemName: String?
    let url: String?
    let size: Double?

    var body: some View {
        let dimension = CGFloat(size ?? 24)
        if let systemName {
            Image(systemName: systemName)
                .resizable()
                .scaledToFit()
                .frame(width: dimension, height: dimension)
        } else if let url, let parsed = URL(string: url) {
            AsyncImage(url: parsed) { img in
                img.resizable().scaledToFit()
            } placeholder: {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
            }
            .frame(width: dimension, height: dimension)
        } else {
            Image(systemName: "photo")
                .frame(width: dimension, height: dimension)
        }
    }
}

struct UIAvatarView: View {
    let systemName: String?
    let url: String?
    let label: String?

    var body: some View {
        HStack(spacing: 8) {
            UIImageView(systemName: systemName, url: url, size: 28)
                .clipShape(Circle())
            if let label {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
        }
    }
}

// MARK: - Interaction

struct UIButtonView: View {
    let label: String
    let action: UIAction
    let systemImage: String?
    let style: String?
    let componentID: String
    let surfaceID: String
    let handler: UIActionHandler
    let catalog: ComponentCatalog

    var body: some View {
        Button {
            guard catalog.allows(action) else { return }
            handler(action, UIActionContext(surfaceID: surfaceID, componentID: componentID))
        } label: {
            if let systemImage {
                Label(label, systemImage: systemImage)
            } else {
                Text(label)
            }
        }
        .modifier(UIButtonStyleModifier(style: style ?? "glass"))
        .disabled(!catalog.allows(action))
    }
}

struct UIButtonStyleModifier: ViewModifier {
    let style: String
    func body(content: Content) -> some View {
        switch style {
        case "bordered":          content.buttonStyle(.bordered)
        case "borderedProminent": content.buttonStyle(.borderedProminent)
        case "plain":             content.buttonStyle(.plain)
        default:                  content.buttonStyle(.glass)
        }
    }
}

struct UILinkView: View {
    let label: String
    let url: String

    var body: some View {
        if let parsed = URL(string: url) {
            Link(label, destination: parsed)
        } else {
            Text(label)
        }
    }
}

struct UIToggleView: View {
    let label: String
    let isOn: Bool
    let action: UIAction
    let componentID: String
    let surfaceID: String
    let handler: UIActionHandler

    @State private var localState: Bool = false

    var body: some View {
        Toggle(label, isOn: Binding(
            get: { localState },
            set: { newValue in
                localState = newValue
                handler(action, UIActionContext(surfaceID: surfaceID, componentID: componentID))
            }
        ))
        .onAppear { localState = isOn }
    }
}

// MARK: - Data

struct UIListView: View {
    let items: [String]
    let style: String?
    let surface: UISurfaceUpdate
    let catalog: ComponentCatalog
    let handler: UIActionHandler

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { id in
                HStack(alignment: .top, spacing: 8) {
                    if style == "bullet" {
                        Text("•").foregroundStyle(.secondary)
                    } else if style == "numbered", let idx = items.firstIndex(of: id) {
                        Text("\(idx + 1).")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    UIComponentRenderer(componentID: id, surface: surface, catalog: catalog, handler: handler)
                }
            }
        }
    }
}

struct UIChartView: View {
    let series: [ChartSeries]
    let kind: String
    let title: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            #if canImport(Charts)
            Chart {
                ForEach(0..<series.count, id: \.self) { i in
                    let s = series[i]
                    ForEach(0..<s.values.count, id: \.self) { j in
                        switch kind {
                        case "bar":
                            BarMark(x: .value("Index", j),
                                    y: .value(s.name, s.values[j]))
                                .foregroundStyle(by: .value("Series", s.name))
                        case "area":
                            AreaMark(x: .value("Index", j),
                                     y: .value(s.name, s.values[j]))
                                .foregroundStyle(by: .value("Series", s.name))
                        default:
                            LineMark(x: .value("Index", j),
                                     y: .value(s.name, s.values[j]))
                                .foregroundStyle(by: .value("Series", s.name))
                        }
                    }
                }
            }
            .frame(height: 140)
            #else
            Text("Charts framework unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
            #endif
        }
    }
}

struct UIKeyValueView: View {
    let pairs: [KeyValuePair]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<pairs.count, id: \.self) { i in
                HStack {
                    Text(pairs[i].key)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(pairs[i].value)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}

struct UITableView: View {
    let columns: [String]
    let rows: [[String]]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                ForEach(0..<columns.count, id: \.self) { idx in
                    Text(columns[idx])
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Divider()
            ForEach(0..<rows.count, id: \.self) { rowIdx in
                let row = rows[rowIdx]
                HStack {
                    ForEach(0..<row.count, id: \.self) { colIdx in
                        Text(row[colIdx])
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}
