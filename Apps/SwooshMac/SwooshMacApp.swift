// Apps/SwooshMac/SwooshMacApp.swift — SwiftPM-built standalone Mac shell
//
// Lightweight entry point for `swift run SwooshMac`. Uses the same
// DashboardView as the XcodeGen app but without the menu-bar extra
// and voice scenes (those require the full Xcode build with metallib).

import SwiftUI
import SwooshUI

@main
struct SwooshMacApp: App {
    @State private var shell = AgentShellModel()
    @State private var didBoot = false

    var body: some Scene {
        WindowGroup("Detour") {
            DashboardView(shell: shell)
                .frame(minWidth: 800, minHeight: 600)
                .task {
                    guard !didBoot else { return }
                    didBoot = true
                    await AgentShellBackends.bootLocalDaemon(shell: shell)
                }
        }
        .windowResizability(.contentSize)
        .commands {
            SidebarCommands()
        }
    }
}
