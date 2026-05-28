// SwooshToolsets/DtourFeeConfig.swift — $DTOUR trade tax + fee sweep configuration
//
// Centralized fee config for all DEX integrations and revenue sources.
// Each platform uses its own fee mechanism but this file defines rates,
// collection accounts, and the 5-way split percentages.
//
// Revenue Sources → $DTOUR:
//   Jupiter swaps (platformFeeBps)    → SOL/USDC/JUP  → swap to $DTOUR
//   Eliza Cloud inference (affiliate) → $ELIZA         → swap to $DTOUR
//   Hyperliquid trades (builder code) → USDC           → bridge + swap
//   Uniswap swaps (hook fee)          → ETH/USDC       → bridge + swap
//   Pump.fun creator fees             → SOL             → swap to $DTOUR
//
// 5-Way Split:
//   40% → Vault stakers (pro-rata by weight)
//   25% → Buyback & burn (permanent supply reduction)
//   15% → Builder rewards (GitHub-verified contributors)
//   10% → Creator rewards (skill/workflow authors)
//   10% → Treasury (development, infrastructure)

import Foundation

/// $DTOUR protocol fee + revenue configuration.
public enum DtourFeeConfig {

    // ── Jupiter (Solana) ─────────────────────────────────────────

    /// Platform fee in basis points for Jupiter swaps (10 = 0.1%).
    public static let defaultBps: Int = 10

    /// Resolve the Swoosh fee collection SPL token account for a
    /// given output mint. Returns nil for unsupported mints.
    public static func feeAccount(for outputMint: String) -> String? {
        switch outputMint {
        case "So11111111111111111111111111111111111111112":     // wSOL
            return "3ssPtzEQc42w5zRMjNZSroQ36cToxUGx5AjD3HZCku9N"
        case "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v":  // USDC
            return "Afkk6kwhiGtRnKwYEJY1XbSG4J8oedB5CXW4zrPy6MLV"
        case "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN":    // JUP
            return "4eNzPMjH2Xw5ggXGLeRbZNgxTdDD5KxqKrFAxMJQ5hya"
        case "DijmsEDeTXsWCkCLkhYJNTutKaHf541xZshVrCUbcozy":   // $DTOUR
            return nil  // TODO: create ATA for $DTOUR fee collection
        default:
            return nil
        }
    }

    // ── Hyperliquid ──────────────────────────────────────────────

    /// Builder fee in tenths of a basis point (10 = 1bps = 0.01%).
    public static let hyperliquidBuilderFeeTenths: Int = 10
    public static let hyperliquidBuilderAddress: String = ""  // TODO: after HL registration

    // ── Uniswap (EVM) ────────────────────────────────────────────

    public static let evmFeeRecipient: String = ""  // TODO: deploy fee collector
    public static let uniswapFeeBps: Int = 10

    // ── Pump.fun Creator Fees ────────────────────────────────────

    /// $DTOUR was launched on pump.fun — the token creator (us) earns
    /// creator fees from trading volume. These are collected via
    /// PumpPortal API and swept through the same 5-way split.
    public static let pumpfunPool: String = "pump"  // pool identifier for PumpPortal

    /// PumpPortal API endpoint for fee collection.
    /// Action: collectCreatorFee, pool: "pump"
    public static let pumpPortalTradeEndpoint = "https://pumpportal.fun/api/trade"

    // ── Fee Split (on-chain, matches dtour-vault program) ────────

    /// How collected fees are distributed (bps, must sum to 10000).
    public static let vaultStakerBps: Int = 4000    // 40% — staker rewards
    public static let buybackBurnBps: Int = 2500     // 25% — burn (deflationary)
    public static let builderRewardBps: Int = 1500   // 15% — GitHub contributors
    public static let creatorRewardBps: Int = 1000   // 10% — skill/workflow authors
    public static let treasuryBps: Int = 1000        // 10% — development

    // ── $DTOUR Token ─────────────────────────────────────────────

    public static let dtourMint = "DijmsEDeTXsWCkCLkhYJNTutKaHf541xZshVrCUbcozy"
}
