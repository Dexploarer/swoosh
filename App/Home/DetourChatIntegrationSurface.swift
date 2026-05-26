// DetourChatIntegrationSurface.swift — chat-driven integration setup cards (0.5A)

import SwiftUI

struct DetourChatIntegrationSurface: Equatable {
    var title: String
    var subtitle: String
    var spec: DetourJSONUISpec
    var items: [DetourIntegrationConnection]
}

@MainActor
enum DetourChatIntegrationSurfaceBuilder {
    static func build(store: OnboardingStore, request: String) -> DetourChatIntegrationSurface? {
        let items = filtered(store.integrationConnectionSnapshot.items, request: request)
        guard !items.isEmpty else { return nil }
        return DetourChatIntegrationSurface(
            title: title(for: request),
            subtitle: "Generated from Detour's safe component manifest.",
            spec: spec(items: items),
            items: items
        )
    }

    static func isIntegrationRequest(_ text: String) -> Bool {
        let value = text.lowercased()
        let words = ["connect", "connector", "integration", "app", "discord", "telegram", "twitter", " x ", "agentmail", "gmail", "slack"]
        return words.contains { value.contains($0) }
    }

    private static func filtered(
        _ items: [DetourIntegrationConnection],
        request: String
    ) -> [DetourIntegrationConnection] {
        let value = request.lowercased()
        let requested = requestedSlugs(value)
        if !requested.isEmpty {
            return items.filter { item in
                requested.contains(item.integration.slug) || requested.contains(item.integration.name.lowercased())
            }
        }
        let priority: Set<String> = ["discord", "telegram", "twitter", "github", "gmail", "slack", "agentmail"]
        let selected = items.filter { $0.selected || $0.state == .detected || priority.contains($0.integration.slug) }
        return Array(selected.prefix(9))
    }

    private static func requestedSlugs(_ value: String) -> Set<String> {
        var slugs = Set<String>()
        if value.contains("discord") { slugs.insert("discord") }
        if value.contains("telegram") { slugs.insert("telegram") }
        if value.contains("twitter") || value.contains(" x ") || value.hasPrefix("x ") { slugs.insert("twitter") }
        if value.contains("github") { slugs.insert("github") }
        if value.contains("gmail") || value.contains("email") { slugs.insert("gmail") }
        if value.contains("slack") { slugs.insert("slack") }
        if value.contains("agentmail") { slugs.insert("agentmail") }
        return slugs
    }

    private static func title(for request: String) -> String {
        requestedSlugs(request.lowercased()).isEmpty ? "Connect apps" : "Set this up"
    }

    private static func spec(items: [DetourIntegrationConnection]) -> DetourJSONUISpec {
        var elements: [String: DetourJSONUIElement] = [
            "root": DetourJSONUIElement(
                type: .shell,
                props: ["title": .string("Integrations"), "subtitle": .string("Connect and test from chat.")],
                children: ["grid"]
            ),
            "grid": DetourJSONUIElement(
                type: .grid,
                props: ["minimumWidth": .number(180)],
                children: items.map { "integration.\($0.id)" }
            ),
        ]
        for item in items {
            elements["integration.\(item.id)"] = DetourJSONUIElement(
                type: .integrationCard,
                props: [
                    "integrationID": .string(item.id),
                    "title": .string(item.integration.name),
                    "status": .string(item.state.label),
                    "scope": .string(item.scope.label),
                ],
                children: []
            )
        }
        return DetourJSONUISpec(root: "root", elements: elements)
    }
}

struct DetourChatIntegrationSurfaceView: View {
    let surface: DetourChatIntegrationSurface
    @ObservedObject var store: OnboardingStore
    @State private var busyIDs: Set<String> = []
    @State private var feedbackByID: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(surface.title)
                        .font(.headline.weight(.semibold))
                    Text(surface.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(surface.spec.streamPatches.count) patches")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                ForEach(surface.items) { item in
                    DetourIntegrationConnectionCard(
                        item: item,
                        connect: { connect(item) },
                        test: { test(item) },
                        setScope: { store.setIntegrationScope(item.integration, role: $0) },
                        isBusy: busyIDs.contains(item.id),
                        feedback: feedbackByID[item.id]
                    )
                }
            }
        }
        .padding(18)
        .detourLiquidGlass(cornerRadius: 24, tint: Color(red: 0.02, green: 0.18, blue: 0.15).opacity(0.44))
        .frame(maxWidth: 850)
    }

    private func connect(_ item: DetourIntegrationConnection) {
        run(item, label: "Connecting...") {
            await DetourIntegrationConnectorSetup.connect(item, store: store)
        }
    }

    private func test(_ item: DetourIntegrationConnection) {
        run(item, label: "Checking...") {
            await DetourIntegrationConnectorSetup.test(item, store: store)
        }
    }

    private func run(
        _ item: DetourIntegrationConnection,
        label: String,
        operation: @escaping () async -> DetourIntegrationSetupResult
    ) {
        busyIDs.insert(item.id)
        feedbackByID[item.id] = label
        Task { @MainActor in
            let result = await operation()
            feedbackByID[item.id] = display(result.message)
            busyIDs.remove(item.id)
        }
    }

    private func display(_ message: String) -> String {
        let value = DetourSetupInsightRedaction.display(message)
        return value.count > 28 ? "\(value.prefix(25))..." : value
    }
}

private extension DetourDelegationRole {
    var label: String {
        switch self {
        case .user:
            return "me"
        case .agent:
            return "agent"
        }
    }
}
