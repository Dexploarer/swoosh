import AppIntents

struct ExampleAgentActionIntent: AppIntent {
    static var title: LocalizedStringResource = "Run Agent Action"
    static var description = IntentDescription("Runs a bounded, privacy-preserving action in the app.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Input")
    var input: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Validate input, call domain service or AgentOrchestrator, map errors to dialog.
        // Keep this safe outside the main app process.
        return .result(dialog: "Done")
    }
}

struct ExampleAgentShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ExampleAgentActionIntent(),
            phrases: ["Run agent action in \(.applicationName)"],
            shortTitle: "Agent Action",
            systemImageName: "sparkles"
        )
    }
}
