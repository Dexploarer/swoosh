import AppIntents

struct ToggleExampleIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Example"

    func perform() async throws -> some IntentResult {
        // Keep widget/control intent work small and deterministic.
        // Call shared extension-safe service, then return.
        return .result()
    }
}
