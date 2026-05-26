// DetourSetupMapView.swift — optional setup topology map (0.5A)

import SwiftUI

struct DetourSetupMapView: View {
    let sections: [DetourSetupInsightSection]

    var body: some View {
        #if os(visionOS)
        if #available(visionOS 26.0, *) {
            spatialMap
        } else {
            fallbackMap
        }
        #else
        fallbackMap
        #endif
    }

    private var fallbackMap: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: 10)], spacing: 10) {
            ForEach(sections) { section in
                DetourSetupSpatialNodeView(section: section)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Setup map")
    }

    #if os(visionOS)
    @available(visionOS 26.0, *)
    private var spatialMap: some View {
        SpatialContainer(alignment: .center) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                DetourSetupSpatialNodeView(section: section)
                    .rotation3DLayout(.degrees(Double(index - sections.count / 2) * 5), axis: .y)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Spatial setup map")
    }
    #endif
}

struct DetourSetupSpatialNodeView: View {
    let section: DetourSetupInsightSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text("\(section.items.count) items")
                .font(.caption2)
                .foregroundStyle(.secondary)
            statusBar
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var statusBar: some View {
        GeometryReader { proxy in
            let total = max(1, section.items.count)
            let attention = section.items.filter(\.status.needsAttention).count
            RoundedRectangle(cornerRadius: 4)
                .fill(attention == 0 ? Color.green.opacity(0.6) : Color.orange.opacity(0.7))
                .frame(width: proxy.size.width * CGFloat(max(1, total - attention)) / CGFloat(total))
        }
        .frame(height: 8)
    }
}
