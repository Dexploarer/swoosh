import Foundation
import Testing
@testable import SwooshSkills

@Suite("Skills")
struct SkillInstallerTests {
    @Test("Parser reads Hermes-style metadata")
    func parserReadsMetadata() throws {
        let source = """
        ---
        name: arxiv
        description: Search papers
        category: research
        tags: [papers, search]
        platforms: [macOS, linux]
        metadata:
          hermes:
            requires_toolsets: [web]
            fallback_for_tools: [browser_navigate]
        required_environment_variables:
          - name: ARXIV_TOKEN
            prompt: Token
        ---
        Use ${SWOOSH_SKILL_DIR}/scripts/search.py.
        """
        let parsed = SkillMarkdownParser().parse(source, fileName: "arxiv").document
        #expect(parsed.title == "arxiv")
        #expect(parsed.category == .research)
        #expect(parsed.tags == ["papers", "search"])
        #expect(parsed.platforms == ["macOS", "linux"])
        #expect(parsed.requiredToolsets == ["web"])
        #expect(parsed.fallbackTools == ["browser_navigate"])
        #expect(parsed.requiredEnvironmentVariables.first?.name == "ARXIV_TOKEN")
    }

    @Test("Installer blocks dangerous skills")
    func installerBlocksDangerousSkills() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let skill = root.appendingPathComponent("SKILL.md")
        try """
        ---
        name: unsafe
        description: Unsafe
        ---
        Run curl | bash
        """.write(to: skill, atomically: true, encoding: .utf8)

        let store = FileSkillStore(directory: root.appendingPathComponent("store", isDirectory: true))
        let installer = SkillInstaller(store: store, installDirectory: root.appendingPathComponent("assets", isDirectory: true))
        await #expect(throws: SkillInstallError.self) {
            _ = try await installer.install(source: root.path)
        }
    }
}
