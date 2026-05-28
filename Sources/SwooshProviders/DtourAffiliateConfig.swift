// SwooshProviders/DtourAffiliateConfig.swift — $DTOUR affiliate revenue config
//
// Every inference call through partnered providers includes an affiliate code.
// Revenue accrues as partner tokens ($ELIZA, etc.) and is swept to $DTOUR
// via the vault reward pool.
//
// Revenue streams:
//   - Detour Cloud (via elizacloud.ai): 20% markup on all API usage → $ELIZA → swap to $DTOUR
//   - Future: OpenRouter, other providers with affiliate programs

import Foundation

/// Affiliate codes for inference provider partnerships.
/// Revenue flows: provider tokens → swap to $DTOUR → vault reward pool.
public enum DtourAffiliateConfig {

    // ── Detour Cloud (upstream: elizacloud.ai) ──────────────────

    /// Swoosh affiliate code for Detour Cloud (elizacloud.ai).
    /// Every API call with this header earns 20% markup as $ELIZA tokens.
    public static let elizaAffiliateCode = "AFF-0GOWANBA"

    /// Detour Cloud referral link for user signups.
    /// Users who sign up get bonus credits; Swoosh earns from their purchases.
    public static let elizaReferralLink = "https://www.elizacloud.ai/login?affiliate=AFF-0GOWANBA"

    /// Current markup percentage on Detour Cloud.
    public static let elizaMarkupPercent: Double = 20.0

    // ── Revenue Flow ─────────────────────────────────────────────
    //
    // 1. Every Detour Cloud API call includes X-Affiliate-Code header
    // 2. 20% markup accrues as $ELIZA tokens in the Swoosh affiliate dashboard
    // 3. swooshd sweep task periodically:
    //    a. Claims $ELIZA from Detour Cloud earnings dashboard
    //    b. Swaps $ELIZA → $DTOUR (via Jupiter or bridge)
    //    c. Deposits $DTOUR into the vault reward pool via sweep_fees
    // 4. Vault stakers + creators earn from inference revenue
    //
    // This means: more users using Swoosh for AI inference = more $DTOUR rewards.
    // Trade tax (from Jupiter/HL/Uni swaps) + inference affiliate revenue
    // are the two income streams feeding the vault.
}
