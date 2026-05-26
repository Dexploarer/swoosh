// DetourIntegrationCatalogView.swift — searchable app connection browser (0.5A)

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct DetourIntegrationCatalogView: View {
    @ObservedObject var store: OnboardingStore
    let scan: () -> Void
    let test: () -> Void
    @State private var query = ""
    @State private var filter = DetourIntegrationFilter.all
    @State private var busyIDs: Set<String> = []
    @State private var feedbackByID: [String: String] = [:]

    var body: some View {
        let snapshot = store.integrationConnectionSnapshot
        let items = filtered(snapshot.items)
        VStack(alignment: .leading, spacing: 16) {
            header(snapshot)
            controls
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(items) { item in
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
    }

    private func header(_ snapshot: DetourIntegrationConnectionSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Apps")
                    .font(.title2.weight(.semibold))
                HStack(spacing: 10) {
                    count("\(snapshot.total)", "available")
                    count("\(snapshot.selected)", "selected")
                    count("\(snapshot.needsSetup)", "fix")
                }
            }
            Spacer()
            Button("Scan", action: scan)
                .buttonStyle(.bordered)
            Button("Test", action: test)
                .buttonStyle(.borderedProminent)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search apps", text: $query)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.white.opacity(0.08), in: Capsule())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DetourIntegrationFilter.allCases) { item in
                        Button(item.rawValue) {
                            filter = item
                        }
                        .buttonStyle(.plain)
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(filter == item ? .white.opacity(0.18) : .white.opacity(0.07), in: Capsule())
                    }
                }
            }
        }
    }

    private func count(_ value: String, _ label: String) -> some View {
        Text("\(value) \(label)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.7))
    }

    private func filtered(_ items: [DetourIntegrationConnection]) -> [DetourIntegrationConnection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            filter.includes(item.integration.category)
                && (trimmed.isEmpty || item.integration.name.localizedCaseInsensitiveContains(trimmed))
        }
    }

    private func connect(_ item: DetourIntegrationConnection) {
        if item.adapterID != nil {
            setFeedback("Connecting...", for: item.id)
            Task { @MainActor in
                await runConnectorSetup(item)
            }
            return
        }
        store.connectIntegration(item.integration)
        if openConfiguration(for: item) {
            setFeedback("Opened setup", for: item.id)
            clearBusyState(for: item.id, after: 1.4)
        } else {
            setFeedback("Needs bridge", for: item.id)
            clearBusyState(for: item.id, after: 2.2)
        }
    }

    private func test(_ item: DetourIntegrationConnection) {
        if item.adapterID != nil {
            setFeedback("Checking...", for: item.id)
            Task { @MainActor in
                await runConnectorTest(item)
            }
            return
        }
        setFeedback("Testing...", for: item.id)
        test()
        clearBusyState(for: item.id, after: 2.0)
    }

    private func setFeedback(_ label: String, for id: String) {
        busyIDs.insert(id)
        feedbackByID[id] = label
    }

    private func clearBusyState(for id: String, after delay: Double) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            busyIDs.remove(id)
            feedbackByID[id] = nil
        }
    }

    private func runConnectorSetup(_ item: DetourIntegrationConnection) async {
        let result = await DetourIntegrationConnectorSetup.connect(item, store: store)
        feedbackByID[item.id] = display(result.message)
        busyIDs.remove(item.id)
    }

    private func runConnectorTest(_ item: DetourIntegrationConnection) async {
        let result = await DetourIntegrationConnectorSetup.test(item, store: store)
        feedbackByID[item.id] = display(result.message)
        busyIDs.remove(item.id)
    }

    private func display(_ message: String) -> String {
        let value = DetourSetupInsightRedaction.display(message)
        return value.count > 28 ? "\(value.prefix(25))..." : value
    }

    private func openConfiguration(for item: DetourIntegrationConnection) -> Bool {
        guard let url = item.configurationURL else { return false }
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        return true
        #else
        return false
        #endif
    }
}
