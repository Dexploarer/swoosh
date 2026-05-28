// SwooshToolsets/DtourFeeSweepEngine.swift — Orchestrates the full fee lifecycle
//
// This actor runs as a background task in swooshd and handles:
//   1. Collecting pump.fun creator fees via PumpPortal API
//   2. Swapping non-DTOUR revenue (SOL, USDC, $ELIZA) to $DTOUR via Jupiter
//   3. Calling sweep_fees on the vault program (5-way split)
//   4. Buyback-only deposits from market purchases
//
// The actual on-chain transactions are built unsigned and submitted
// through the existing Solana broadcast pipeline.

import Foundation

/// Orchestrates $DTOUR fee collection, buyback, burn, and distribution.
///
/// ## Sweep Cycle (runs on schedule in swooshd)
///
/// ```
/// ┌─────────────────────────────────────────────────────────┐
/// │  1. Collect pump.fun creator fees (PumpPortal API)      │
/// │     POST /api/trade { action: "collectCreatorFee" }     │
/// │     → receives SOL                                      │
/// │                                                         │
/// │  2. Check fee account balances (Jupiter SOL, USDC, JUP) │
/// │     → RPC getTokenAccountBalance for each fee ATA       │
/// │                                                         │
/// │  3. Swap all non-DTOUR to $DTOUR via Jupiter            │
/// │     → platformFeeBps=0 (no fee-on-fee)                  │
/// │     → all output goes to protocol admin ATA             │
/// │                                                         │
/// │  4. Call sweep_fees on dtour-vault program               │
/// │     → 40% vault reward pool (stakers)                   │
/// │     → 25% burn (native token::burn, permanent)          │
/// │     → 15% builder pool (GitHub contributors)            │
/// │     → 10% creator pool (skill/workflow authors)         │
/// │     → 10% treasury (development)                        │
/// │                                                         │
/// │  5. Optionally: buyback_deposit for non-burn buybacks   │
/// │     → admin buys $DTOUR from market at discount         │
/// │     → deposits into reward pool for extra staker yield  │
/// └─────────────────────────────────────────────────────────┘
/// ```
public actor DtourFeeSweepEngine {

    /// Fee account balances to check before sweeping.
    public struct FeeAccountBalance: Codable, Sendable {
        public let mint: String
        public let account: String
        public let balance: UInt64
    }

    /// Result of a sweep cycle.
    public struct SweepResult: Codable, Sendable {
        public let timestamp: Date
        public let pumpfunCollected: UInt64       // SOL lamports from pump.fun
        public let totalSwappedToDtour: UInt64    // $DTOUR from all swaps
        public let vaultAmount: UInt64            // 40% to stakers
        public let burnAmount: UInt64             // 25% burned permanently
        public let builderAmount: UInt64          // 15% to contributors
        public let creatorAmount: UInt64          // 10% to skill authors
        public let treasuryAmount: UInt64         // 10% to development
        public let sweepTxSignature: String?
    }

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // ── Step 1: Collect pump.fun creator fees ────────────────────

    /// Collect accumulated creator fees from pump.fun via PumpPortal.
    /// Returns the transaction signature on success.
    public func collectPumpfunFees(apiKey: String) async throws -> String {
        guard let url = URL(string: DtourFeeConfig.pumpPortalTradeEndpoint + "?api-key=\(apiKey)") else {
            throw SweepError.invalidConfig("Bad PumpPortal URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "action": "collectCreatorFee",
            "pool": DtourFeeConfig.pumpfunPool,
            "priorityFee": 0.000005
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let signature = json["signature"] as? String else {
            throw SweepError.pumpfunCollectionFailed("No signature in response")
        }

        return signature
    }

    // ── Step 2: Check fee account balances ───────────────────────

    /// Check balances of all fee collection accounts.
    public func checkFeeBalances(rpcURL: String) async throws -> [FeeAccountBalance] {
        var balances: [FeeAccountBalance] = []

        // Check each known fee account
        let accounts: [(mint: String, account: String)] = [
            ("So11111111111111111111111111111111111111112",
             "3ssPtzEQc42w5zRMjNZSroQ36cToxUGx5AjD3HZCku9N"),
            ("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
             "Afkk6kwhiGtRnKwYEJY1XbSG4J8oedB5CXW4zrPy6MLV"),
            ("JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN",
             "4eNzPMjH2Xw5ggXGLeRbZNgxTdDD5KxqKrFAxMJQ5hya"),
        ]

        for (mint, account) in accounts {
            if let balance = try await getTokenBalance(rpcURL: rpcURL, account: account) {
                balances.append(FeeAccountBalance(mint: mint, account: account, balance: balance))
            }
        }

        return balances
    }

    // ── Helpers ───────────────────────────────────────────────────

    private func getTokenBalance(rpcURL: String, account: String) async throws -> UInt64? {
        guard let url = URL(string: rpcURL) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getTokenAccountBalance",
            "params": [account]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let value = result["value"] as? [String: Any],
              let amountStr = value["amount"] as? String,
              let amount = UInt64(amountStr) else {
            return nil
        }

        return amount
    }

    public enum SweepError: Error, Sendable {
        case invalidConfig(String)
        case pumpfunCollectionFailed(String)
        case swapFailed(String)
        case sweepTxFailed(String)
    }
}
