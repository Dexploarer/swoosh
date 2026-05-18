// Tests/SwooshToolsTests/JupiterToolTests.swift
// Unit tests for Jupiter swap tools and BigInt-backed quantity types.
// Network calls are mocked via protocol substitution — no real API calls.

import Testing
import Foundation
@testable import SwooshTools
@testable import SwooshToolsets

// MARK: - BigInt quantity tests

@Suite("EVMQuantity (BigInt-backed)")
struct EVMQuantityTests {
    @Test("Hex init round-trips")
    func hexRoundTrip() {
        let q = EVMQuantity("0xde0b6b3a7640000") // 1 ETH in wei
        #expect(q.hexString == "0xde0b6b3a7640000")
        #expect(q.hex == q.hexString)
    }

    @Test("Decimal UInt64 init produces correct hex")
    func decimalInit() {
        let q = EVMQuantity(UInt64(1_000_000_000)) // 1 gwei
        #expect(q.asGwei == 1.0)
        #expect(q.value > 0)
    }

    @Test("ETH conversion from wei")
    func ethConversion() {
        // 1 ETH = 1e18 wei
        let q = EVMQuantity("0xde0b6b3a7640000")
        #expect(abs(q.asETH - 1.0) < 0.0001)
    }

    @Test("Arithmetic — addition")
    func addition() {
        let a = EVMQuantity(UInt64(100))
        let b = EVMQuantity(UInt64(200))
        #expect((a + b).value == 300)
    }

    @Test("Arithmetic — comparison")
    func comparison() {
        let small = EVMQuantity(UInt64(1))
        let large = EVMQuantity(UInt64(999))
        #expect(small < large)
    }

    @Test("JSON encode/decode round-trip")
    func jsonRoundTrip() throws {
        let q = EVMQuantity("0xabc123")
        let data = try JSONEncoder().encode(q)
        let decoded = try JSONDecoder().decode(EVMQuantity.self, from: data)
        #expect(decoded.hexString == q.hexString)
    }
}

@Suite("Lamports (BigInt-backed)")
struct LamportsTests {
    @Test("SOL conversion")
    func solConversion() {
        let l = Lamports(UInt64(1_000_000_000))
        #expect(l.asSOL == 1.0)
    }

    @Test("Addition")
    func addition() {
        let a = Lamports(UInt64(500_000_000))
        let b = Lamports(UInt64(500_000_000))
        #expect((a + b).asSOL == 1.0)
    }

    @Test("JSON round-trip")
    func jsonRoundTrip() throws {
        let l = Lamports(UInt64(12_345_678))
        let data = try JSONEncoder().encode(l)
        let decoded = try JSONDecoder().decode(Lamports.self, from: data)
        #expect(decoded.value == l.value)
    }
}

// MARK: - Jupiter tool metadata tests (no network)

@Suite("Jupiter tool metadata")
struct JupiterToolMetadataTests {
    @Test("Quote tool is readOnly + never needs approval")
    func quoteMeta() {
        #expect(JupiterQuoteTool.risk == .readOnly)
        #expect(JupiterQuoteTool.approval == .never)
    }

    @Test("Swap tool is critical + askEveryTime")
    func swapMeta() {
        #expect(JupiterSwapTool.risk == .critical)
        #expect(JupiterSwapTool.approval == .askEveryTime)
    }

    @Test("Execute tool is critical + askEveryTime")
    func executeMeta() {
        #expect(JupiterExecuteTool.risk == .critical)
        #expect(JupiterExecuteTool.approval == .askEveryTime)
    }

    @Test("Balances tool is readOnly + never")
    func balancesMeta() {
        #expect(JupiterBalancesTool.risk == .readOnly)
        #expect(JupiterBalancesTool.approval == .never)
    }

    @Test("Build order is high risk + askEveryTime")
    func buildOrderMeta() {
        #expect(JupiterBuildOrderTool.risk == .high)
        #expect(JupiterBuildOrderTool.approval == .askEveryTime)
    }

    @Test("All Jupiter tools are in solana toolset")
    func toolsets() {
        #expect(JupiterQuoteTool.toolset == .solana)
        #expect(JupiterSwapTool.toolset == .solana)
        #expect(JupiterBalancesTool.toolset == .solana)
    }
}

// MARK: - Jupiter input validation tests

@Suite("Jupiter input types")
struct JupiterInputTests {
    @Test("QuoteInput default slippage is 50bps")
    func quoteDefaultSlippage() {
        let q = JupiterQuoteInput(
            inputMint: "So11111111111111111111111111111111111111112",
            outputMint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            amountLamports: "1000000"
        )
        #expect(q.slippageBps == 50)
    }

    @Test("SwapInput custom slippage")
    func swapCustomSlippage() {
        let s = JupiterSwapInput(
            inputMint: "So111111111111111111111111111111111111111",
            outputMint: "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN",
            amountLamports: "5000000",
            walletSessionID: "sess-abc",
            slippageBps: 100
        )
        #expect(s.slippageBps == 100)
        #expect(s.walletSessionID == "sess-abc")
    }

    @Test("Swap — fails without wallet bridge")
    func swapNoWallet() async {
        let deps = ToolDependencies(
            firewall: MockFirewall(granted: [.solanaBroadcast]),
            audit: MockAudit(),
            approvals: MockApprovals(),
            fileAccess: StubFileAccess(),
            processRunner: StubProcessRunner(),
            walletBridge: nil
        )
        let tool = JupiterSwapTool(dependencies: deps)
        let input = JupiterSwapInput(
            inputMint: "So11111111111111111111111111111111111111112",
            outputMint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            amountLamports: "1000000",
            walletSessionID: "sess-x"
        )
        do {
            _ = try await tool.call(input, context: ToolContext(sessionID: "test"))
            Issue.record("Expected error — no wallet bridge")
        } catch ToolError.executionFailed(let msg) {
            #expect(msg.contains("wallet") || msg.contains("No wallet"))
        } catch {}
    }
}
