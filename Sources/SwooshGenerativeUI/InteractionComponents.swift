// SwooshGenerativeUI/InteractionComponents.swift — Built-in interactive component views (0.4A)

import SwiftUI

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
        case "bordered": content.buttonStyle(.bordered)
        case "borderedProminent": content.buttonStyle(.borderedProminent)
        case "plain": content.buttonStyle(.plain)
        default: content.buttonStyle(.glass)
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
    let catalog: ComponentCatalog

    @State private var localState: Bool

    init(
        label: String,
        isOn: Bool,
        action: UIAction,
        componentID: String,
        surfaceID: String,
        handler: @escaping UIActionHandler,
        catalog: ComponentCatalog
    ) {
        self.label = label
        self.isOn = isOn
        self.action = action
        self.componentID = componentID
        self.surfaceID = surfaceID
        self.handler = handler
        self.catalog = catalog
        self._localState = State(initialValue: isOn)
    }

    var body: some View {
        Toggle(label, isOn: Binding(
            get: { localState },
            set: { newValue in
                guard catalog.allows(action) else { return }
                localState = newValue
                handler(action, UIActionContext(surfaceID: surfaceID, componentID: componentID))
            }
        ))
        .disabled(!catalog.allows(action))
        .onChange(of: isOn) { _, newValue in localState = newValue }
    }
}
