// Tests/SwooshToolsTests/UniswapToolTests.swift
// Unit tests for all Uniswap V3 tools.
// Tests: metadata, fee tier enum, ABI encoding helpers, input validation,
// pool address sorting, and guard clauses.
// No network calls — all RPC paths guarded behind evmClient nil check.

import Testing
import Foundation
import BigInt
@testable import SwooshTools
@testable import SwooshToolsets

// MARK: - Helpers

private func deps(evmClient: (any EVMRPCClient)? = nil) -> ToolDependencies {
    ToolDependencies(
        firewall: MockFirewall(granted: Set(SwooshPermission.allCases)),
        audit: MockAudit(),
        approvals: MockApprovals(),
        fileAccess: StubFileAccess(),
        processRunner: StubProcessRunner(),
        evmClient: evmClient
    )
}

private func ctx() -> ToolContext { ToolContext(sessionID: "uni-test") }

// MARK: - Fee tier enum

@Suite("Uniswap Fee Tier")
struct UniswapFeeTierTests {
    @Test("Fee tier raw values are correct")
    func rawValues() {
        #expect(UniswapFeeTier.fee100.rawValue == 100)
        #expect(UniswapFeeTier.fee500.rawValue == 500)
        #expect(UniswapFeeTier.fee3000.rawValue == 3000)
        #expect(UniswapFeeTier.fee10000.rawValue == 10000)
    }

    @Test("Fee tier labels are human-readable")
    func labels() {
        #expect(UniswapFeeTier.fee100.label == "0.01%")
        #expect(UniswapFeeTier.fee500.label == "0.05%")
        #expect(UniswapFeeTier.fee3000.label == "0.30%")
        #expect(UniswapFeeTier.fee10000.label == "1.00%")
    }

    @Test("Fee tier bps matches rawValue")
    func bps() {
        for tier in UniswapFeeTier.allCases {
            #expect(tier.bps == tier.rawValue)
        }
    }

    @Test("4 fee tiers defined")
    func count() {
        #expect(UniswapFeeTier.allCases.count == 4)
    }

    @Test("Fee tier is Codable")
    func codable() throws {
        let data = try JSONEncoder().encode(UniswapFeeTier.fee3000)
        let decoded = try JSONDecoder().decode(UniswapFeeTier.self, from: data)
        #expect(decoded == .fee3000)
    }
}

// MARK: - Quote tool metadata and inputs

@Suite("Uniswap Quote Tool")
struct UniswapQuoteToolTests {
    @Test("Quote is readOnly + evmRead + never approval")
    func meta() {
        #expect(UniswapQuoteTool.risk == .readOnly)
        #expect(UniswapQuoteTool.permission == .evmRead)
        #expect(UniswapQuoteTool.approval == .never)
        #expect(UniswapQuoteTool.toolset == .uniswap)
    }

    @Test("Quote fails without EVM client")
    func quoteNoClient() async {
        let tool = UniswapQuoteTool(dependencies: deps(evmClient: nil))
        let input = UniswapQuoteInput(
            tokenIn: EVMAddress("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"),
            tokenOut: EVMAddress("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"),
            amountIn: EVMQuantity(BigInt(1_000_000_000_000_000_000)),
            feeTier: .fee500,
            rpcURLSecretRef: "eth.rpc"
        )
        do {
            _ = try await tool.call(input, context: ctx())
            Issue.record("Expected error — no EVM client")
        } catch ToolError.executionFailed(let msg) {
            #expect(msg.contains("EVM RPC") || msg.contains("No EVM"))
        } catch {}
    }

    @Test("Quote input stores all fields")
    func quoteInput() {
        let weth = EVMAddress("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2")
        let usdc = EVMAddress("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48")
        let input = UniswapQuoteInput(
            tokenIn: weth, tokenOut: usdc,
            amountIn: EVMQuantity(BigInt(1_000_000_000_000_000_000)),
            feeTier: .fee500, rpcURLSecretRef: "eth.rpc"
        )
        #expect(input.feeTier == .fee500)
        #expect(input.rpcURLSecretRef == "eth.rpc")
    }

    @Test("Quote output types hold BigInt-backed quantities")
    func quoteOutput() {
        let out = UniswapQuoteOutput(
            amountOut: EVMQuantity(BigInt(1_000_000)),
            amountOutMin: EVMQuantity(BigInt(995_000)),
            priceImpactBps: 15,
            feeTier: .fee3000,
            sqrtPriceX96After: "0xabcdef",
            gasEstimate: EVMQuantity(BigInt(150_000))
        )
        #expect(out.amountOut.value > out.amountOutMin.value)
        #expect(out.feeTier == .fee3000)
        #expect(out.sqrtPriceX96After.hasPrefix("0x"))
    }
}

// MARK: - Build swap tool

@Suite("Uniswap Build Swap Tool")
struct UniswapSwapToolTests {
    @Test("BuildSwap is high + evmBuildTransaction + askEveryTime")
    func meta() {
        #expect(UniswapSwapTool.risk == .high)
        #expect(UniswapSwapTool.permission == .evmBuildTransaction)
        #expect(UniswapSwapTool.approval == .askEveryTime)
        #expect(UniswapSwapTool.toolset == .uniswap)
    }

    @Test("BuildSwap fails without EVM client")
    func swapNoClient() async {
        let tool = UniswapSwapTool(dependencies: deps(evmClient: nil))
        let input = UniswapSwapInput(
            tokenIn: EVMAddress("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"),
            tokenOut: EVMAddress("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"),
            amountIn: EVMQuantity(BigInt(1_000_000_000_000_000_000)),
            amountOutMin: EVMQuantity(BigInt(995_000_000)),
            feeTier: .fee3000,
            recipient: EVMAddress("0xdeadbeef00000000000000000000000000000001")
        )
        do {
            _ = try await tool.call(input, context: ctx())
            Issue.record("Expected error")
        } catch ToolError.executionFailed(let msg) {
            #expect(msg.contains("EVM RPC") || msg.contains("No EVM"))
        } catch {}
    }

    @Test("BuildSwap input stores deadline and fee tier")
    func swapInput() {
        let input = UniswapSwapInput(
            tokenIn: EVMAddress("0xA"),
            tokenOut: EVMAddress("0xB"),
            amountIn: EVMQuantity(BigInt(1_000_000)),
            amountOutMin: EVMQuantity(BigInt(990_000)),
            feeTier: .fee100,
            recipient: EVMAddress("0xC"),
            deadlineSeconds: 600
        )
        #expect(input.feeTier == .fee100)
        #expect(input.deadlineSeconds == 600)
        #expect(input.amountIn.value > input.amountOutMin.value)
    }

    @Test("BuildSwap default deadline is 1200 seconds")
    func defaultDeadline() {
        let input = UniswapSwapInput(
            tokenIn: EVMAddress("0xA"), tokenOut: EVMAddress("0xB"),
            amountIn: EVMQuantity(BigInt(1)), amountOutMin: EVMQuantity(BigInt(1)),
            recipient: EVMAddress("0xC")
        )
        #expect(input.deadlineSeconds == 1200)
    }
}

// MARK: - Pool address tool

@Suite("Uniswap Pool Address Tool")
struct UniswapPoolToolTests {
    @Test("PoolAddress is readOnly + evmRead + never approval")
    func meta() {
        #expect(UniswapPoolTool.risk == .readOnly)
        #expect(UniswapPoolTool.permission == .evmRead)
        #expect(UniswapPoolTool.approval == .never)
        #expect(UniswapPoolTool.toolset == .uniswap)
    }

    @Test("Pool sorts tokenA < tokenB (token0 has smaller address hex)")
    func poolSortTokens() async throws {
        let tool = UniswapPoolTool(dependencies: deps())
        // USDC < WETH lexicographically
        let usdc = EVMAddress("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48")
        let weth = EVMAddress("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2")
        let input = UniswapPoolInput(tokenA: weth, tokenB: usdc, feeTier: .fee500)
        let output = try await tool.call(input, context: ctx())
        // token0 must be lexicographically smaller
        #expect(output.token0.hex.lowercased() < output.token1.hex.lowercased())
        #expect(output.feeTier == .fee500)
    }

    @Test("Pool sorting is commutative — same result regardless of input order")
    func poolSortCommutative() async throws {
        let tool = UniswapPoolTool(dependencies: deps())
        let usdc = EVMAddress("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48")
        let weth = EVMAddress("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2")
        let inputAB = UniswapPoolInput(tokenA: usdc, tokenB: weth, feeTier: .fee3000)
        let inputBA = UniswapPoolInput(tokenA: weth, tokenB: usdc, feeTier: .fee3000)
        let outAB = try await tool.call(inputAB, context: ctx())
        let outBA = try await tool.call(inputBA, context: ctx())
        #expect(outAB.token0.hex == outBA.token0.hex)
        #expect(outAB.token1.hex == outBA.token1.hex)
    }

    @Test("Pool output includes fee tier")
    func poolOutputFee() async throws {
        let tool = UniswapPoolTool(dependencies: deps())
        let input = UniswapPoolInput(
            tokenA: EVMAddress("0x1111111111111111111111111111111111111111"),
            tokenB: EVMAddress("0x2222222222222222222222222222222222222222"),
            feeTier: .fee10000
        )
        let output = try await tool.call(input, context: ctx())
        #expect(output.feeTier == .fee10000)
    }

    @Test("Pool address matches canonical Uniswap V3 CREATE2 output")
    func poolAddressMatchesKnownMainnetPool() async throws {
        let tool = UniswapPoolTool(dependencies: deps())
        let input = UniswapPoolInput(
            tokenA: EVMAddress("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"),
            tokenB: EVMAddress("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"),
            feeTier: .fee500
        )
        let output = try await tool.call(input, context: ctx())
        #expect(output.poolAddress.hex == "0x88e6a0c2ddd26feeb64f039a2c41296fcb3f5640")
    }
}

// MARK: - Permission and toolset IDs

@Suite("Uniswap toolset configuration")
struct UniswapToolsetTests {
    @Test("All Uniswap tool names are unique")
    func uniqueNames() {
        let names: [ToolName] = [
            UniswapQuoteTool.name,
            UniswapSwapTool.name,
            UniswapPoolTool.name,
        ]
        #expect(Set(names).count == names.count, "Duplicate Uniswap tool name")
    }

    @Test("All Uniswap tools use .uniswap toolset")
    func uniswapToolset() {
        let toolsets: [ToolsetID] = [
            UniswapQuoteTool.toolset,
            UniswapSwapTool.toolset,
            UniswapPoolTool.toolset,
        ]
        #expect(toolsets.allSatisfy { $0 == .uniswap })
    }

    @Test("ToolsetID has both .hyperliquid and .uniswap cases")
    func toolsetIDs() {
        #expect(ToolsetID.allCases.contains(.hyperliquid))
        #expect(ToolsetID.allCases.contains(.uniswap))
    }
}

// MARK: - SecretResolving infrastructure

@Suite("SecretResolving protocol")
struct SecretResolvingTests {
    @Test("NullSecretResolver always throws")
    func nullResolverThrows() async {
        let resolver = NullSecretResolver()
        do {
            _ = try await resolver.resolve(ref: "any.secret")
            Issue.record("Expected throw")
        } catch ToolError.executionFailed(let msg) {
            #expect(msg.contains("SecretResolver") || msg.contains("any.secret"))
        } catch {}
    }

    @Test("NullSecretResolver is the default in ToolDependencies")
    func defaultResolver() async {
        // If no secrets param provided, NullSecretResolver is used.
        let d = ToolDependencies(
            firewall: MockFirewall(granted: []),
            audit: MockAudit(),
            approvals: MockApprovals(),
            fileAccess: StubFileAccess(),
            processRunner: StubProcessRunner()
        )
        do {
            _ = try await d.secrets.resolve(ref: "test")
            Issue.record("Expected NullSecretResolver to throw")
        } catch {
            // Any error means the null resolver fired
        }
    }

    @Test("SwooshPermission has networkRead, hyperliquidTrade, hyperliquidTransfer")
    func newPermissions() {
        #expect(SwooshPermission.allCases.contains(.networkRead))
        #expect(SwooshPermission.allCases.contains(.hyperliquidTrade))
        #expect(SwooshPermission.allCases.contains(.hyperliquidTransfer))
    }
}
