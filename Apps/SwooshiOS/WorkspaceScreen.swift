// Apps/SwooshiOS/WorkspaceScreen.swift — Customizable iOS workspace
//
// Hosts the PanelHost with surface "ios". Default layout (defined in
// PanelLayoutStore.defaultLayout) lands a sensible set of capsules;
// user drags-reorders and add/removes via edit mode.

import SwiftUI
import SwooshGenerativeUI
import SwooshUI

struct WorkspaceScreen: View {
    @Environment(AgentShellModel.self) private var shell
    @State private var store = PanelLayoutStore()
    @State private var editing = false

    var body: some View {
        PanelHost(
            store: store,
            surface: "ios",
            context: PanelHostContext(shell: shell),
            editing: $editing
        )
        .navigationTitle("Workspace")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Single edit toggle for iPhone. PanelHost only adds its own
            // toolbar items on regular-width screens, so this is the
            // canonical "rearrange" affordance here.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.spring(duration: 0.2)) { editing.toggle() }
                } label: {
                    Label(
                        editing ? "Done" : "Edit",
                        systemImage: editing ? "checkmark.circle.fill" : "square.grid.2x2"
                    )
                    .labelStyle(.titleAndIcon)
                }
            }
        }
    }
}
