// onchain/programs/swoosh-protocol/src/lib.rs
//
// Dtour Protocol — on-chain enforcement for Swoosh agent crypto toolsets.
//
// Accounts:
//   ProtocolConfig — global config PDA (authority, mint, treasury, rates)
//   StakeAccount   — per-wallet per-toolset escrow PDA
//   AnchorRecord   — per-batch Merkle root PDA
//   RebateClaim    — per-wallet per-epoch claim tracker PDA
//
// Instructions:
//   initialize      — create config + treasury (authority only)
//   stake           — deposit $DTOUR, protocol fee skimmed to treasury
//   unstake         — withdraw after cooldown
//   anchor_batch    — submit Merkle root (requires active stake)
//   claim_rebate    — claim earned rebates for an epoch
//   update_config   — change rates/requirements (authority only)

use anchor_lang::prelude::*;

pub mod errors;
pub mod instructions;
pub mod state;

use instructions::*;

// Placeholder — replace after `solana-keygen grind` or first `anchor build`
declare_id!("11111111111111111111111111111112");

#[program]
pub mod swoosh_protocol {
    use super::*;

    /// Initialize the protocol config and treasury token account.
    pub fn initialize(
        ctx: Context<Initialize>,
        stake_requirements: [u64; 5],
        rebate_rate_bps: u16,
        protocol_fee_bps: u16,
        unstake_cooldown_seconds: i64,
    ) -> Result<()> {
        instructions::initialize::handler(
            ctx,
            stake_requirements,
            rebate_rate_bps,
            protocol_fee_bps,
            unstake_cooldown_seconds,
        )
    }

    /// Deposit $DTOUR tokens to stake for a toolset.
    pub fn stake(ctx: Context<Stake>, amount: u64, toolset_index: u8) -> Result<()> {
        instructions::stake::handler(ctx, amount, toolset_index)
    }

    /// Withdraw staked $DTOUR after cooldown.
    pub fn unstake(ctx: Context<Unstake>, amount: u64) -> Result<()> {
        instructions::unstake::handler(ctx, amount)
    }

    /// Submit a batch of receipt Merkle roots on-chain.
    pub fn anchor_batch(
        ctx: Context<AnchorBatchIx>,
        merkle_root: [u8; 32],
        entry_count: u32,
        toolset_index: u8,
        epoch: u32,
    ) -> Result<()> {
        instructions::anchor_batch::handler(ctx, merkle_root, entry_count, toolset_index, epoch)
    }

    /// Claim rebates for a completed epoch.
    pub fn claim_rebate(ctx: Context<ClaimRebate>, epoch: u32) -> Result<()> {
        instructions::claim_rebate::handler(ctx, epoch)
    }

    /// Update protocol parameters (authority only).
    pub fn update_config(
        ctx: Context<UpdateConfig>,
        stake_requirements: Option<[u64; 5]>,
        rebate_rate_bps: Option<u16>,
        protocol_fee_bps: Option<u16>,
        unstake_cooldown_seconds: Option<i64>,
    ) -> Result<()> {
        instructions::update_config::handler(
            ctx,
            stake_requirements,
            rebate_rate_bps,
            protocol_fee_bps,
            unstake_cooldown_seconds,
        )
    }
}
