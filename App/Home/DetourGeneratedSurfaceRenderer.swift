// DetourGeneratedSurfaceRenderer.swift — SwiftUI renderer for generated home surfaces (0.5A)

import SwiftUI

struct DetourGeneratedSurfaceRenderer: View {
    let surface: DetourGeneratedSurface
    @ObservedObject var store: OnboardingStore
    @ObservedObject var wallet: DetourHomeWalletModel
    @ObservedObject var inbox: DetourHomeInboxModel
    let socialItems: [DetourSetupInsightItem]
    let runScan: () -> Void
    let reviewSetup: () -> Void
    let applySetup: () -> Void
    let action: (DetourGeneratedAction) -> Void

    var body: some View {
        render(surface.rootID)
    }

    private func render(_ id: String) -> AnyView {
        if let component = surface.component(id: id) {
            return render(component.body)
        }
        return AnyView(EmptyView())
    }

    private func render(_ body: DetourGeneratedComponentBody) -> AnyView {
        switch body {
        case let .column(children, spacing):
            return AnyView(VStack(alignment: .leading, spacing: spacing) {
                ForEach(children, id: \.self) { render($0) }
            })
        case let .row(children, spacing):
            return AnyView(HStack(alignment: .top, spacing: spacing) {
                ForEach(children, id: \.self) { render($0) }
            })
        case let .grid(children, minimumWidth):
            return AnyView(LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: 12)], spacing: 12) {
                ForEach(children, id: \.self) { render($0) }
            })
        case let .panel(child, tone):
            return AnyView(render(child)
                .padding(18)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                .overlay {
                    RoundedRectangle(cornerRadius: 22).stroke(tone.color.opacity(0.16), lineWidth: 1)
                })
        case let .heading(title, subtitle):
            return AnyView(heading(title: title, subtitle: subtitle))
        case let .hero(agentName, summary, workspace):
            return AnyView(hero(agentName: agentName, summary: summary, workspace: workspace))
        case let .metric(title, value, detail, tone):
            return AnyView(metric(title: title, value: value, detail: detail, tone: tone))
        case let .status(label, tone):
            return AnyView(Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(tone.color.opacity(0.14), in: Capsule())
                .foregroundStyle(tone.color))
        case let .button(title, systemImage, itemAction, prominent):
            if prominent {
                return AnyView(Button {
                    action(itemAction)
                } label: {
                    Label(title, systemImage: systemImage)
                }
                .buttonStyle(.borderedProminent))
            }
            return AnyView(Button {
                action(itemAction)
            } label: {
                Label(title, systemImage: systemImage)
            }
            .buttonStyle(.bordered))
        case let .chips(title, subtitle, chips, overflow):
            return AnyView(chipGroup(title: title, subtitle: subtitle, chips: chips, overflow: overflow))
        case let .socialConnector(connector):
            return AnyView(socialConnector(connector))
        case let .nativePanel(panel):
            return AnyView(nativePanel(panel))
        case let .setupItem(item):
            return AnyView(DetourHomeItemRow(item: item) { action(.setupInsight($0)) })
        case let .inboxItem(item):
            return AnyView(inboxItem(item))
        case let .message(title, detail, tone):
            return AnyView(message(title: title, detail: detail, tone: tone))
        }
    }

    @ViewBuilder
    private func nativePanel(_ panel: DetourGeneratedNativePanel) -> some View {
        switch panel {
        case .apps:
            DetourIntegrationCatalogView(
                store: store,
                scan: runScan,
                test: applySetup
            )
        case .socialOnChain:
            DetourHomeCryptoPanel(
                wallet: wallet,
                socialItems: socialItems,
                reviewSetup: reviewSetup,
                applySetup: applySetup
            )
        case .universalInbox:
            DetourHomeInboxPanel(
                inbox: inbox,
                reviewSetup: reviewSetup
            )
        case .settings:
            DetourHomeSettingsPanel(
                store: store,
                scan: runScan,
                applySetup: applySetup,
                reviewSetup: reviewSetup
            )
        }
    }

    private func heading(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.weight(.semibold))
            if let subtitle {
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func hero(agentName: String, summary: String, workspace: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(.white.opacity(0.10))
                Image(systemName: "sparkles").foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(agentName).font(.headline.weight(.semibold))
                Text(summary).font(.caption).foregroundStyle(.white.opacity(0.62)).lineLimit(2)
            }
            Spacer()
            Text(workspace).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.48))
        }
    }

    private func metric(title: String, value: String, detail: String, tone: DetourGeneratedTone) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 28, weight: .semibold, design: .rounded))
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).stroke(tone.color.opacity(0.14), lineWidth: 1)
        }
    }

    private func chipGroup(
        title: String,
        subtitle: String?,
        chips: [DetourGeneratedChip],
        overflow: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if overflow > 0 {
                    Text("+\(overflow)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            FlowLayout(spacing: 8) {
                ForEach(chips) { chip in
                    Text(chip.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(chip.tone.color.opacity(0.16), in: Capsule())
                        .foregroundStyle(chip.tone.color)
                }
            }
        }
    }

    private func socialConnector(_ connector: DetourGeneratedConnector) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: connector.systemImage).foregroundStyle(connector.tone.color)
                Spacer()
                render(.status(label: connector.status, tone: connector.tone))
            }
            Text(connector.name).font(.headline)
            Text(connector.detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            render(.button(
                title: connector.ready ? "Test" : "Set up",
                systemImage: connector.ready ? "checkmark.shield" : "slider.horizontal.3",
                action: connector.ready ? .applySetup : .reviewSetup,
                prominent: false
            ))
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }

    private func inboxItem(_ item: DetourHomeInboxItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(item.healthy ? .green : .orange).frame(width: 8, height: 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.callout.weight(.semibold)).lineLimit(1)
                Text(item.preview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Text(item.kind.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func message(title: String, detail: String, tone: DetourGeneratedTone) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tone.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }
}

extension DetourGeneratedTone {
    var color: Color {
        switch self {
        case .accent: .accentColor
        case .blue: .blue
        case .green: .green
        case .indigo: .indigo
        case .orange: .orange
        case .secondary: .secondary
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let width = proposal.width ?? 320
        let rows = rows(for: subviews, width: width)
        let height = rows.reduce(CGFloat.zero) { partial, row in
            partial + row.height + (partial == 0 ? 0 : spacing)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [FlowRow] {
        var rows: [FlowRow] = []
        var current = FlowRow(items: [], width: 0, height: 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextWidth = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if nextWidth > width, !current.items.isEmpty {
                rows.append(current)
                current = FlowRow(items: [], width: 0, height: 0)
            }
            current.items.append(FlowItem(index: index, size: size))
            current.width = current.items.count == 1 ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
        }
        if !current.items.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

private struct FlowRow {
    var items: [FlowItem]
    var width: CGFloat
    var height: CGFloat
}

private struct FlowItem {
    var index: Int
    var size: CGSize
}
