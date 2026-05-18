// WidgetExtension/SwooshWidgetBundle.swift — Widget extension entry point

import WidgetKit
import SwiftUI
import SwooshWidgets

@main
struct SwooshWidgetBundle: WidgetBundle {
    var body: some Widget {
        SwooshProviderWidget()
        SwooshCommandWidget()
        SwooshDashboardWidget()
    }
}
