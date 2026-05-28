// state.rs — On-chain account structures for the Dtour Protocol.

use anchor_lang::prelude::*;

// ── Toolset indices ──────────────────────────────────────────────────
// Matches SwooshTools.ToolsetID.isCrypto families:
//   0 = evm, 1 = solana, 2 = hyperliquid, 3 = uniswap, 4 = launchpads

pub const TOOLSET_COUNT: usize = 5;

// ── Protocol Config ──────────────────────────────────────────────────

/// Global protocol configuration. One per deployment.
/// PDA seeds: ["config"]
#[account]
pub struct ProtocolConfig {
    /// Authority keypair that can update config.
    pub authority: Pubkey,
    /// $DTOUR SPL token mint.
    pub token_mint: Pubkey,
    /// Treasury token account (receives protocol fees, pays rebates).
    pub treasury: Pubkey,
    /// Minimum stake (in token base units) per toolset index.
    pub stake_requirements: [u64; TOOLSET_COUNT],
    /// Rebate rate in basis points per anchored receipt.
    pub rebate_rate_bps: u16,
    /// Protocol fee in basis points, taken from each stake deposit.
    pub protocol_fee_bps: u16,
    /// Seconds a wallet must wait after last activity before unstaking.
    pub unstake_cooldown_seconds: i64,
    /// Running totals for protocol health metrics.
    pub total_staked: u64,
    pub total_anchored_batches: u64,
    pub total_rebates_paid: u64,
    /// PDA bump seed.
    pub bump: u8,
}

impl ProtocolConfig {
    // 8 (discriminator) + 32 + 32 + 32 + 40 + 2 + 2 + 8 + 8 + 8 + 8 + 1 = 181
    pub const SPACE: usize = 8 + 32 + 32 + 32 + (8 * TOOLSET_COUNT) + 2 + 2 + 8 + 8 + 8 + 8 + 1;
}

// ── Stake Account ────────────────────────────────────────────────────

/// Per-wallet per-toolset stake escrow.
/// PDA seeds: ["stake", wallet, [toolset_index]]
#[account]
pub struct StakeAccount {
    /// Wallet that owns this stake.
    pub wallet: Pubkey,
    /// Toolset index (0–4).
    pub toolset_index: u8,
    /// Amount of $DTOUR currently staked (base units).
    pub amount: u64,
    /// Unix timestamp when first staked.
    pub staked_at: i64,
    /// Unix timestamp of most recent anchor_batch or stake top-up.
    pub last_activity_at: i64,
    /// The PDA-owned token account holding the staked tokens.
    pub vault: Pubkey,
    /// PDA bump seed.
    pub bump: u8,
}

impl StakeAccount {
    // 8 + 32 + 1 + 8 + 8 + 8 + 32 + 1 = 98
    pub const SPACE: usize = 8 + 32 + 1 + 8 + 8 + 8 + 32 + 1;
}

// ── Anchor Record ────────────────────────────────────────────────────

/// On-chain record of a submitted Merkle root batch.
/// PDA seeds: ["anchor", submitter, merkle_root]
#[account]
pub struct AnchorRecord {
    /// Wallet that submitted this batch.
    pub submitter: Pubkey,
    /// Merkle root of the receipt batch (SHA-256).
    pub merkle_root: [u8; 32],
    /// Number of audit entries in the batch.
    pub entry_count: u32,
    /// Unix timestamp of submission.
    pub submitted_at: i64,
    /// Which toolset family this batch covers.
    pub toolset_index: u8,
    /// PDA bump seed.
    pub bump: u8,
}

impl AnchorRecord {
    // 8 + 32 + 32 + 4 + 8 + 1 + 1 = 86
    pub const SPACE: usize = 8 + 32 + 32 + 4 + 8 + 1 + 1;
}

// ── Rebate Claim ─────────────────────────────────────────────────────

/// Per-wallet per-epoch rebate claim tracker.
/// PDA seeds: ["rebate", wallet, epoch.to_le_bytes()]
#[account]
pub struct RebateClaim {
    /// Wallet this claim belongs to.
    pub wallet: Pubkey,
    /// Epoch number (quarterly, monotonically increasing).
    pub epoch: u32,
    /// Count of anchored receipt batches in this epoch.
    pub anchored_receipts: u32,
    /// Total $DTOUR claimed for this epoch (base units).
    pub claimed_amount: u64,
    /// Whether the claim has been executed.
    pub claimed: bool,
    /// PDA bump seed.
    pub bump: u8,
}

impl RebateClaim {
    // 8 + 32 + 4 + 4 + 8 + 1 + 1 = 58
    pub const SPACE: usize = 8 + 32 + 4 + 4 + 8 + 1 + 1;
}
