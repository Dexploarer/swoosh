import Testing
import Foundation
@testable import SwooshTools
@testable import SwooshToolsets

@Suite("Launchpad Tools")
struct LaunchpadToolTests {
    @Test("Launchpad tool metadata is read-only")
    func metadata() {
        #expect(LaunchpadListPlatformsTool.risk == .readOnly)
        #expect(LaunchpadListPlatformsTool.permission == .toolRead)
        #expect(LaunchpadListPlatformsTool.approval == .never)
        #expect(LaunchpadListPlatformsTool.toolset == .launchpads)
        #expect(LaunchpadGetPlatformTool.toolset == .launchpads)
        #expect(ToolsetID.allCases.contains(.launchpads))
    }

    @Test("Catalog lists all launchpad platforms")
    func listPlatforms() async throws {
        let output = try await LaunchpadListPlatformsTool()
            .call(LaunchpadListPlatformsInput(), context: ToolContext(sessionID: "launchpads-test"))
        let ids = Set(output.platforms.map(\.id))

        #expect(ids == ["pumpportal", "bags", "flap", "four-meme"])
        #expect(output.platforms.first(where: { $0.id == "pumpportal" })?.capabilities.contains("pumpswap-buy-sell") == true)
        #expect(output.platforms.first(where: { $0.id == "four-meme" })?.capabilities.contains("tax-token-planning") == true)
    }

    @Test("Catalog returns platform detail")
    func getPlatform() async throws {
        let output = try await LaunchpadGetPlatformTool().call(
            LaunchpadGetPlatformInput(id: "flap"),
            context: ToolContext(sessionID: "launchpads-test")
        )

        #expect(output.detail.platform.name == "Flap")
        #expect(output.detail.requiredPermissions.contains("evmBuildTransaction"))
        #expect(output.detail.docs.contains { $0.title == "VaultPortal launch" })
    }

    @Test("Registrar exposes launchpad tools")
    func registrarExposesLaunchpadTools() async {
        let registry = ToolRegistry(
            firewall: MockFirewall(granted: [.toolRead]),
            audit: MockAudit(),
            approvals: MockApprovals()
        )
        await DefaultToolRegistrar.registerLaunchpads(into: registry)

        let tools = await registry.listAvailable(context: ToolContext(sessionID: "launchpads-test"))
        let names = Set(tools.map(\.name))

        #expect(names.contains("launchpad.list_platforms"))
        #expect(names.contains("launchpad.get_platform"))
        #expect(tools.filter { $0.toolset == .launchpads }.count == 2)
    }
}
