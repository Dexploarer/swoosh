// instructions/anchor_batch.rs — Submit a Merkle root on-chain.
//
// Creates an AnchorRecord PDA. Requires the submitter to have an
// active StakeAccount for the given toolset with sufficient balance.
// Also increments the RebateClaim counter for the given epoch.
//
// The caller (daemon) computes the current epoch and passes it in.
// PDA seeds use the epoch directly so each quarterly period gets
// its own RebateClaim account.

use anchor_lang::prelude::*;

use crate::errors::DtourError;
use crate::state::{AnchorRecord, ProtocolConfig, RebateClaim, StakeAccount, TOOLSET_COUNT};

#[derive(Accounts)]
#[instruction(merkle_root: [u8; 32], entry_count: u32, toolset_index: u8, epoch: u32)]
pub struct AnchorBatchIx<'info> {
    /// Wallet submitting the batch.
    #[account(mut)]
    pub submitter: Signer<'info>,

    /// Protocol config (read for stake requirements).
    #[account(
        mut,
        seeds = [b"config"],
        bump = config.bump,
    )]
    pub config: Account<'info, ProtocolConfig>,

    /// Submitter's stake for the given toolset — must exist and meet minimum.
    #[account(
        mut,
        seeds = [b"stake", submitter.key().as_ref(), &[toolset_index]],
        bump = stake_account.bump,
        constraint = stake_account.wallet == submitter.key() @ DtourError::Unauthorized,
    )]
    pub stake_account: Account<'info, StakeAccount>,

    /// Anchor record PDA — created for this batch.
    #[account(
        init,
        payer = submitter,
        space = AnchorRecord::SPACE,
        seeds = [b"anchor", submitter.key().as_ref(), merkle_root.as_ref()],
        bump,
    )]
    pub anchor_record: Account<'info, AnchorRecord>,

    /// Rebate claim tracker — created or updated for the given epoch.
    #[account(
        init_if_needed,
        payer = submitter,
        space = RebateClaim::SPACE,
        seeds = [b"rebate", submitter.key().as_ref(), &epoch.to_le_bytes()],
        bump,
    )]
    pub rebate_claim: Account<'info, RebateClaim>,

    pub system_program: Program<'info, System>,
}

pub fn handler(
    ctx: Context<AnchorBatchIx>,
    merkle_root: [u8; 32],
    entry_count: u32,
    toolset_index: u8,
    epoch: u32,
) -> Result<()> {
    require!(
        (toolset_index as usize) < TOOLSET_COUNT,
        DtourError::InvalidToolsetIndex
    );
    require!(entry_count > 0, DtourError::InvalidMerkleRoot);

    let config = &ctx.accounts.config;
    let stake = &ctx.accounts.stake_account;
    let clock = Clock::get()?;
    let now = clock.unix_timestamp;

    // ── Stake requirement check ──
    let required = config.stake_requirements[toolset_index as usize];
    require!(stake.amount >= required, DtourError::InsufficientStake);

    // ── Write anchor record ──
    let record = &mut ctx.accounts.anchor_record;
    record.submitter = ctx.accounts.submitter.key();
    record.merkle_root = merkle_root;
    record.entry_count = entry_count;
    record.submitted_at = now;
    record.toolset_index = toolset_index;
    record.bump = ctx.bumps.anchor_record;

    // ── Update rebate claim counter ──
    let claim = &mut ctx.accounts.rebate_claim;
    if claim.wallet == Pubkey::default() {
        // First-time init for this epoch
        claim.wallet = ctx.accounts.submitter.key();
        claim.epoch = epoch;
        claim.claimed = false;
        claim.claimed_amount = 0;
        claim.bump = ctx.bumps.rebate_claim;
    }
    claim.anchored_receipts = claim
        .anchored_receipts
        .checked_add(entry_count)
        .unwrap();

    // ── Update stake last-activity timestamp ──
    let stake = &mut ctx.accounts.stake_account;
    stake.last_activity_at = now;

    // ── Update config counters ──
    let config = &mut ctx.accounts.config;
    config.total_anchored_batches = config.total_anchored_batches.checked_add(1).unwrap();

    msg!(
        "Anchored batch: {} entries, toolset {}, epoch {}, root {:?}",
        entry_count,
        toolset_index,
        epoch,
        &merkle_root[..8]
    );
    Ok(())
}
