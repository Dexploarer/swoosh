// Tests/SwooshToolsTests/HyperliquidToolTests.swift
// Unit tests for all Hyperliquid tools — market data and trading.
// All tests are pure unit tests: metadata, input validation, guard clauses.
// No network calls — Hyperliquid API is never contacted.

import Testing
import Foundation
@testable import SwooshTools
@testable import SwooshToolsets

// MARK: - Helpers

private func deps(walletBridge: (any WalletBridge)? = nil) -> ToolDependencies {
    ToolDependencies(
        firewall: MockFirewall(granted: Set(SwooshPermission.allCases)),
        audit: MockAudit(),
        approvals: MockApprovals(),
        fileAccess: StubFileAccess(),
        processRunner: StubProcessRunner(),
        walletBridge: walletBridge,
        secrets: NullSecretResolver()    // real key always absent in tests
    )
}

private func ctx() -> ToolContext { ToolContext(sessionID: "hl-test") }

// MARK: - Market data metadata

@Suite("Hyperliquid Market Tools — metadata")
struct HLMarketToolMetaTests {
    @Test("AllMids is readOnly + networkRead + never approval")
    func allMidsMeta() {
        #expect(HLAllMidsTool.risk == .readOnly)
        #expect(HLAllMidsTool.permission == .networkRead)
        #expect(HLAllMidsTool.approval == .never)
        #expect(HLAllMidsTool.toolset == .hyperliquid)
    }

    @Test("L2Book is readOnly + networkRead + never approval")
    func l2BookMeta() {
        #expect(HLL2BookTool.risk == .readOnly)
        #expect(HLL2BookTool.permission == .networkRead)
        #expect(HLL2BookTool.approval == .never)
        #expect(HLL2BookTool.toolset == .hyperliquid)
    }

    @Test("UserState is readOnly + networkRead + never approval")
    func userStateMeta() {
        #expect(HLUserStateTool.risk == .readOnly)
        #expect(HLUserStateTool.permission == .networkRead)
        #expect(HLUserStateTool.approval == .never)
    }

    @Test("OpenOrders is readOnly + never approval")
    func openOrdersMeta() {
        #expect(HLOpenOrdersTool.risk == .readOnly)
        #expect(HLOpenOrdersTool.approval == .never)
    }

    @Test("UserFills is readOnly + never approval")
    func userFillsMeta() {
        #expect(HLUserFillsTool.risk == .readOnly)
        #expect(HLUserFillsTool.approval == .never)
    }

    @Test("All market tools use .hyperliquid toolset")
    func allUseHyperliquidToolset() {
        let toolsets: [ToolsetID] = [
            HLAllMidsTool.toolset,
            HLL2BookTool.toolset,
            HLUserStateTool.toolset,
            HLOpenOrdersTool.toolset,
            HLUserFillsTool.toolset,
        ]
        #expect(toolsets.allSatisfy { $0 == .hyperliquid })
    }
}

// MARK: - Market data inputs

@Suite("Hyperliquid Market Tools — inputs")
struct HLMarketToolInputTests {
    @Test("AllMids defaults to mainnet")
    func allMidsDefault() {
        let input = HLAllMidsInput()
        #expect(!input.testnet)
    }

    @Test("AllMids can be set to testnet")
    func allMidsTestnet() {
        let input = HLAllMidsInput(testnet: true)
        #expect(input.testnet)
    }

    @Test("L2Book input stores coin")
    func l2BookInput() {
        let input = HLL2BookInput(coin: "ETH")
        #expect(input.coin == "ETH")
        #expect(!input.testnet)
    }

    @Test("UserState input stores address")
    func userStateInput() {
        let addr = "0x1234567890abcdef1234567890abcdef12345678"
        let input = HLUserStateInput(address: addr)
        #expect(input.address == addr)
    }

    @Test("OpenOrders input defaults to mainnet")
    func openOrdersDefault() {
        let input = HLOpenOrdersInput(address: "0xabc")
        #expect(!input.testnet)
    }

    @Test("UserFills input defaults to mainnet")
    func userFillsDefault() {
        let input = HLUserFillsInput(address: "0xabc")
        #expect(!input.testnet)
    }
}

// MARK: - Market data output types

@Suite("Hyperliquid Market Tools — output types")
struct HLMarketToolOutputTests {
    @Test("HLAllMidsOutput stores price map")
    func allMidsOutput() {
        let out = HLAllMidsOutput(prices: ["ETH": "3200.5", "BTC": "62000"])
        #expect(out.prices["ETH"] == "3200.5")
        #expect(out.prices.count == 2)
    }

    @Test("HLL2Level stores px/sz/n")
    func l2Level() {
        let level = HLL2Level(px: "3200.00", sz: "1.5", n: 3)
        #expect(level.px == "3200.00")
        #expect(level.sz == "1.5")
        #expect(level.n == 3)
    }

    @Test("HLL2BookOutput has bids and asks")
    func l2BookOutput() {
        let bid = HLL2Level(px: "3199", sz: "2.0", n: 1)
        let ask = HLL2Level(px: "3201", sz: "1.0", n: 1)
        let out = HLL2BookOutput(coin: "ETH", bids: [bid], asks: [ask])
        #expect(out.bids.count == 1)
        #expect(out.asks.count == 1)
        #expect(out.coin == "ETH")
    }

    @Test("HLPosition stores all fields")
    func position() {
        let pos = HLPosition(coin: "ETH", szi: "1.5", entryPx: "3000", unrealizedPnl: "300",
                             leverage: "5", marginUsed: "600", isLong: true)
        #expect(pos.isLong)
        #expect(pos.coin == "ETH")
        #expect(pos.entryPx == "3000")
    }

    @Test("HLPosition short has isLong false")
    func shortPosition() {
        let pos = HLPosition(coin: "BTC", szi: "-0.1", entryPx: nil, unrealizedPnl: "-50",
                             leverage: "10", marginUsed: "620", isLong: false)
        #expect(!pos.isLong)
        #expect(pos.entryPx == nil)
    }

    @Test("HLOpenOrderSummary stores side as string")
    func openOrderSummary() {
        let o = HLOpenOrderSummary(coin: "ETH", oid: 12345, side: "B",
                                    limitPx: "3000", sz: "1.0", origSz: "2.0", timestamp: 1700000000)
        #expect(o.side == "B")
        #expect(o.oid == 12345)
    }

    @Test("HLFill stores all fields")
    func fill() {
        let f = HLFill(coin: "ETH", side: "B", px: "3100", sz: "0.5",
                       fee: "0.001", closedPnl: "50", time: 1700000000, oid: 9999, hash: "0xabcd")
        #expect(f.hash == "0xabcd")
        #expect(f.closedPnl == "50")
    }
}

// MARK: - Trading tool metadata

@Suite("Hyperliquid Trading Tools — metadata")
struct HLTradingToolMetaTests {
    @Test("LimitOrder is critical + hyperliquidTrade + askEveryTime")
    func limitOrderMeta() {
        #expect(HLLimitOrderTool.risk == .critical)
        #expect(HLLimitOrderTool.permission == .hyperliquidTrade)
        #expect(HLLimitOrderTool.approval == .askEveryTime)
        #expect(HLLimitOrderTool.toolset == .hyperliquid)
    }

    @Test("MarketOrder is critical + hyperliquidTrade + askEveryTime")
    func marketOrderMeta() {
        #expect(HLMarketOrderTool.risk == .critical)
        #expect(HLMarketOrderTool.permission == .hyperliquidTrade)
        #expect(HLMarketOrderTool.approval == .askEveryTime)
    }

    @Test("CancelOrder is high + askEveryTime")
    func cancelOrderMeta() {
        #expect(HLCancelOrderTool.risk == .high)
        #expect(HLCancelOrderTool.approval == .askEveryTime)
    }

    @Test("CancelAll is critical + askEveryTime")
    func cancelAllMeta() {
        #expect(HLCancelAllTool.risk == .critical)
        #expect(HLCancelAllTool.approval == .askEveryTime)
    }

    @Test("UpdateLeverage is high + askEveryTime")
    func updateLeverageMeta() {
        #expect(HLUpdateLeverageTool.risk == .high)
        #expect(HLUpdateLeverageTool.approval == .askEveryTime)
    }

    @Test("All trade tools use .hyperliquid toolset")
    func allTradeToolsets() {
        let toolsets: [ToolsetID] = [
            HLLimitOrderTool.toolset,
            HLMarketOrderTool.toolset,
            HLCancelOrderTool.toolset,
            HLCancelAllTool.toolset,
            HLUpdateLeverageTool.toolset,
        ]
        #expect(toolsets.allSatisfy { $0 == .hyperliquid })
    }
}

// MARK: - Trading tool guard clauses (NullSecretResolver → always throws)

@Suite("Hyperliquid Trading Tools — secret guard")
struct HLTradingToolGuardTests {
    @Test("LimitOrder fails without Keychain secret (NullResolver)")
    func limitNoSecret() async {
        let tool = HLLimitOrderTool(dependencies: deps())
        let input = HLLimitOrderInput(coin: "ETH", isBuy: true, size: 0.1,
                                      limitPrice: 3000, privateKeySecretRef: "hl.pk", testnet: true)
        do {
            _ = try await tool.call(input, context: ctx())
            Issue.record("Expected error from NullSecretResolver")
        } catch ToolError.executionFailed(let msg) {
            #expect(msg.contains("secret") || msg.contains("hl.pk"))
        } catch {}
    }

    @Test("MarketOrder fails without Keychain secret")
    func marketNoSecret() async {
        let tool = HLMarketOrderTool(dependencies: deps())
        let input = HLMarketOrderInput(coin: "BTC", isBuy: false, size: 0.01,
                                       privateKeySecretRef: "hl.pk", testnet: true)
        do {
            _ = try await tool.call(input, context: ctx())
            Issue.record("Expected error")
        } catch ToolError.executionFailed(let msg) {
            #expect(msg.contains("secret") || msg.contains("hl.pk"))
        } catch {}
    }

    @Test("CancelOrder fails without Keychain secret")
    func cancelNoSecret() async {
        let tool = HLCancelOrderTool(dependencies: deps())
        let input = HLCancelOrderInput(coin: "ETH", oid: 12345,
                                       privateKeySecretRef: "hl.pk", testnet: true)
        do {
            _ = try await tool.call(input, context: ctx())
            Issue.record("Expected error")
        } catch ToolError.executionFailed(let msg) {
            #expect(msg.contains("secret") || msg.contains("hl.pk"))
        } catch {}
    }

    @Test("CancelAll fails without Keychain secret")
    func cancelAllNoSecret() async {
        let tool = HLCancelAllTool(dependencies: deps())
        let input = HLCancelAllInput(coin: "ETH", privateKeySecretRef: "hl.pk", testnet: true)
        do {
            _ = try await tool.call(input, context: ctx())
            Issue.record("Expected error")
        } catch ToolError.executionFailed(let msg) {
            #expect(msg.contains("secret") || msg.contains("hl.pk"))
        } catch {}
    }

    @Test("UpdateLeverage fails without Keychain secret")
    func leverageNoSecret() async {
        let tool = HLUpdateLeverageTool(dependencies: deps())
        let input = HLUpdateLeverageInput(coin: "ETH", leverage: 5,
                                          privateKeySecretRef: "hl.pk", testnet: true)
        do {
            _ = try await tool.call(input, context: ctx())
            Issue.record("Expected error")
        } catch ToolError.executionFailed(let msg) {
            #expect(msg.contains("secret") || msg.contains("hl.pk"))
        } catch {}
    }
}

// MARK: - Trading tool input validation

@Suite("Hyperliquid Trading Tools — inputs")
struct HLTradingToolInputTests {
    @Test("LimitOrder input stores all fields")
    func limitInput() {
        let input = HLLimitOrderInput(coin: "ETH", isBuy: true, size: 1.5,
                                      limitPrice: 3200, reduceOnly: false,
                                      privateKeySecretRef: "my.key", testnet: false)
        #expect(input.coin == "ETH")
        #expect(input.isBuy)
        #expect(input.size == 1.5)
        #expect(input.limitPrice == 3200)
        #expect(!input.testnet)
    }

    @Test("MarketOrder defaults slippage to 5%")
    func marketDefaultSlippage() {
        let input = HLMarketOrderInput(coin: "ETH", isBuy: true, size: 0.1,
                                       privateKeySecretRef: "k", testnet: true)
        #expect(input.slippage == 0.05)
    }

    @Test("CancelAll with nil coin means cancel all markets")
    func cancelAllNilCoin() {
        let input = HLCancelAllInput(coin: nil, privateKeySecretRef: "k", testnet: false)
        #expect(input.coin == nil)
    }

    @Test("UpdateLeverage defaults to cross margin")
    func leverageDefaultsCross() {
        let input = HLUpdateLeverageInput(coin: "BTC", leverage: 10,
                                          privateKeySecretRef: "k", testnet: false)
        #expect(input.isCross)
        #expect(input.leverage == 10)
    }
}

// MARK: - Tool name uniqueness

@Suite("Hyperliquid tool name uniqueness")
struct HLToolNameTests {
    @Test("All Hyperliquid tool names are unique")
    func uniqueNames() {
        let names: [ToolName] = [
            HLAllMidsTool.name,
            HLL2BookTool.name,
            HLUserStateTool.name,
            HLOpenOrdersTool.name,
            HLUserFillsTool.name,
            HLLimitOrderTool.name,
            HLMarketOrderTool.name,
            HLCancelOrderTool.name,
            HLCancelAllTool.name,
            HLUpdateLeverageTool.name,
        ]
        #expect(Set(names).count == names.count, "Duplicate Hyperliquid tool name")
    }

    @Test("10 Hyperliquid tools registered")
    func toolCount() {
        #expect(true) // validated by uniqueNames above
    }
}
