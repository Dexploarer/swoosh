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

    @Test("Parser reads block-list metadata")
    func parserReadsBlockListMetadata() throws {
        let source = """
        ---
        name: jupiter
        description: Jupiter skill
        tags:
          - jupiter
          - swap
        triggers:
          - quote
          - trade
        platforms:
          - macOS
          - linux
        ---
        Body.
        """

        let parsed = SkillMarkdownParser().parse(source, fileName: "jupiter").document
        #expect(parsed.tags == ["jupiter", "swap"])
        #expect(parsed.triggerPatterns == ["quote", "trade"])
        #expect(parsed.platforms == ["macOS", "linux"])
    }

    @Test("Bundled loader includes Jupiter agent skills")
    func bundledLoaderIncludesJupiterAgentSkills() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Skills/Bundled/jup-ag-agent-skills", isDirectory: true)
        let storeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = FileSkillStore(directory: storeRoot)
        let loader = BundledSkillLoader(store: store, directory: root)

        let loaded = try await loader.loadAll()
        let titles = Set(loaded.map(\.title))
        #expect(titles == [
            "integrating-jupiter",
            "jupiter-lend",
            "jupiter-swap-migration",
            "jupiter-vrfd"
        ])

        guard let integration = loaded.first(where: { $0.title == "integrating-jupiter" }) else {
            Issue.record("Missing integrating-jupiter skill")
            return
        }
        #expect(integration.tags.contains("jupiter"))
        #expect(integration.supportingFiles.contains("examples/swap.md"))
        #expect(integration.trust == .promoted)
        #expect(integration.provenance.source == .builtIn)
    }

    @Test("Bundled loader includes Pay and PancakeSwap agent skills")
    func bundledLoaderIncludesPayAndPancakeSwapAgentSkills() async throws {
        let bundleRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Skills/Bundled", isDirectory: true)
        let storeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = FileSkillStore(directory: storeRoot)

        let payLoaded = try await BundledSkillLoader(
            store: store,
            directory: bundleRoot.appendingPathComponent("pay-sh", isDirectory: true)
        ).loadAll()
        let pancakeLoaded = try await BundledSkillLoader(
            store: store,
            directory: bundleRoot.appendingPathComponent("pancakeswap-ai", isDirectory: true)
        ).loadAll()

        #expect(Set(payLoaded.map(\.title)) == ["pay-sh-api-wallet"])
        #expect(Set(pancakeLoaded.map(\.title)) == [
            "collect-fees",
            "farming-planner",
            "harvest-rewards",
            "hub-api-integration",
            "hub-swap-planner",
            "liquidity-planner",
            "swap-integration",
            "swap-planner",
        ])

        guard let paySkill = payLoaded.first,
              let swapSkill = pancakeLoaded.first(where: { $0.title == "swap-planner" }) else {
            Issue.record("Missing Pay or PancakeSwap bundled skills")
            return
        }
        #expect(paySkill.tags.contains("x402"))
        #expect(paySkill.triggerPatterns.contains("HTTP 402"))
        #expect(paySkill.requiredToolsets == ["mcp"])
        #expect(swapSkill.description.contains("PancakeSwap"))
        #expect(swapSkill.supportingFiles.contains("../common/token-lists.md"))
        #expect(swapSkill.trust == .promoted)
        #expect(swapSkill.provenance.source == .builtIn)
    }

    @Test("Bundled loader includes launchpad agent skills")
    func bundledLoaderIncludesLaunchpadAgentSkills() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Skills/Bundled/launchpads", isDirectory: true)
        let storeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = FileSkillStore(directory: storeRoot)
        let loader = BundledSkillLoader(store: store, directory: root)

        let loaded = try await loader.loadAll()
        let titles = Set(loaded.map(\.title))
        #expect(titles == [
            "bags-launchpad",
            "flap-launchpad",
            "four-meme-launchpad",
            "pumpportal-launchpad",
        ])

        guard let pumpPortal = loaded.first(where: { $0.title == "pumpportal-launchpad" }),
              let fourMeme = loaded.first(where: { $0.title == "four-meme-launchpad" }) else {
            Issue.record("Missing launchpad bundled skills")
            return
        }
        #expect(pumpPortal.tags.contains("pumpportal"))
        #expect(pumpPortal.requiredToolsets.contains("solana"))
        #expect(fourMeme.tags.contains("pancakeswap"))
        #expect(fourMeme.requiredToolsets.contains("evm"))
        #expect(fourMeme.trust == .promoted)
        #expect(fourMeme.provenance.source == .builtIn)
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
