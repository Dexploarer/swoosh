// errors.rs — Custom error codes for the Dtour Protocol.

use anchor_lang::prelude::*;

#[error_code]
pub enum DtourError {
    #[msg("Insufficient stake for this toolset")]
    InsufficientStake,

    #[msg("Cooldown period has not elapsed since last activity")]
    CooldownNotElapsed,

    #[msg("Rebate already claimed for this epoch")]
    AlreadyClaimed,

    #[msg("Treasury has insufficient funds for rebate payout")]
    TreasuryDepleted,

    #[msg("Invalid Merkle root (must be 32 bytes)")]
    InvalidMerkleRoot,

    #[msg("Unauthorized — only the protocol authority can perform this action")]
    Unauthorized,

    #[msg("Invalid toolset index (must be 0–4)")]
    InvalidToolsetIndex,

    #[msg("Unstake amount exceeds staked balance")]
    InsufficientStakeBalance,

    #[msg("No anchored receipts to claim rebates for")]
    NoReceiptsToClaim,

    #[msg("Protocol fee basis points exceed maximum (10000)")]
    InvalidFeeBps,

    #[msg("Rebate rate basis points exceed maximum (10000)")]
    InvalidRebateRate,
}
