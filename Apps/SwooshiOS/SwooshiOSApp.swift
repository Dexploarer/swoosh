import SwiftUI
import SwooshUI

@main
struct SwooshiOSApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                DashboardView()
                    .navigationTitle("Swoosh")
            }
        }
    }
}
