import SwiftUI
import SwooshUI

@main
struct SwooshMacApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowResizability(.contentSize)
        .commands {
            SidebarCommands()
        }
    }
}
