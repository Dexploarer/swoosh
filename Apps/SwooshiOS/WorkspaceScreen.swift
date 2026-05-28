// Apps/SwooshiOS/WorkspaceScreen.swift — Customizable iOS workspace
//
// A segmented-pane view displaying the live agent database states:
//   • Memories — approved / pending / rejected semantic memories
//   • Skills   — promoted / draft / frozen bundled capabilities
//   • Tools    — active tool catalog & permission gates
//   • Audit    — real-time execution timeline of decisions
//
// Aligned with the flagship macOS tabbed panel layout.

import SwiftUI
import SwooshGenerativeUI
import SwooshUI

struct WorkspaceScreen: View {
    @Environment(AgentShellModel.self) private var shell
    @State private var selectedTab: WorkspaceTab = .memories

    enum WorkspaceTab: String, CaseIterable, Identifiable {
        case memories = "Memories"
        case skills = "Skills"
        case tools = "Tools"
        case audit = "Audit"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .memories: return "brain.head.profile"
            case .skills: return "lightbulb"
            case .tools: return "wrench.and.screwdriver"
            case .audit: return "list.bullet.rectangle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Segmented selector aligned with neon theme tokens
            Picker("Workspace Tab", selection: $selectedTab) {
                ForEach(WorkspaceTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(SwooshNeonTokens.Canvas.bg)

            Divider()
                .background(SwooshNeonTokens.Line.rule)

            // Selected Pane Content
            Group {
                switch selectedTab {
                case .memories:
                    MemoriesPane()
                case .skills:
                    SkillsPane()
                case .tools:
                    ToolsPane()
                case .audit:
                    AuditPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SwooshNeonTokens.Canvas.bg)
        .navigationTitle("Workspace")
        .navigationBarTitleDisplayMode(.inline)
    }
}
