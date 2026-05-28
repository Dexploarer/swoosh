// instructions/claim_rebate.rs — Claim earned $DTOUR rebates for an epoch.
//
// Formula: rebate = anchored_receipts * rebate_rate_bps / 10_000
// (where each receipt is worth 1 base unit of the rebate rate)
//
// Transfers from the treasury (PDA-signed by config) to the wallet.

use anchor_lang::prelude::*;
use anchor_spl::token::{self, Mint, Token, TokenAccount, Transfer};

use crate::errors::DtourError;
use crate::state::{ProtocolConfig, RebateClaim};

#[derive(Accounts)]
#[instruction(epoch: u32)]
pub struct ClaimRebate<'info> {
    /// Wallet claiming rebates.
    #[account(mut)]
    pub wallet: Signer<'info>,

    /// Protocol config (read for rebate rate, signs treasury transfer).
    #[account(
        mut,
        seeds = [b"config"],
        bump = config.bump,
    )]
    pub config: Account<'info, ProtocolConfig>,

    /// $DTOUR mint (read for decimals context).
    #[account(address = config.token_mint)]
    pub token_mint: Account<'info, Mint>,

    /// Rebate claim PDA for this wallet + epoch.
    #[account(
        mut,
        seeds = [b"rebate", wallet.key().as_ref(), &epoch.to_le_bytes()],
        bump = rebate_claim.bump,
        has_one = wallet,
    )]
    pub rebate_claim: Account<'info, RebateClaim>,

    /// Treasury token account (source of rebate payout).
    #[account(
        mut,
        address = config.treasury,
    )]
    pub treasury: Account<'info, TokenAccount>,

    /// Wallet's token account (destination).
    #[account(mut)]
    pub wallet_token_account: Account<'info, TokenAccount>,

    pub token_program: Program<'info, Token>,
}

pub fn handler(ctx: Context<ClaimRebate>, _epoch: u32) -> Result<()> {
    let claim = &ctx.accounts.rebate_claim;

    // ── Validation ──
    require!(!claim.claimed, DtourError::AlreadyClaimed);
    require!(claim.anchored_receipts > 0, DtourError::NoReceiptsToClaim);

    let config = &ctx.accounts.config;

    // ── Compute rebate amount ──
    // Each anchored receipt earns (rebate_rate_bps / 10_000) tokens.
    // We use the mint's decimal factor for meaningful amounts.
    let decimals_factor = 10u64.pow(ctx.accounts.token_mint.decimals as u32);
    let rebate_amount = (claim.anchored_receipts as u64)
        .checked_mul(config.rebate_rate_bps as u64)
        .unwrap()
        .checked_mul(decimals_factor)
        .unwrap()
        .checked_div(10_000)
        .unwrap();

    // ── Treasury balance check ──
    require!(
        ctx.accounts.treasury.amount >= rebate_amount,
        DtourError::TreasuryDepleted
    );

    // ── Transfer from treasury → wallet (config PDA signer) ──
    let bump_slice = [config.bump];
    let seeds: &[&[u8]] = &[b"config", &bump_slice];
    let signer_seeds = &[seeds];

    let transfer_ctx = CpiContext::new_with_signer(
        ctx.accounts.token_program.to_account_info(),
        Transfer {
            from: ctx.accounts.treasury.to_account_info(),
            to: ctx.accounts.wallet_token_account.to_account_info(),
            authority: ctx.accounts.config.to_account_info(),
        },
        signer_seeds,
    );
    token::transfer(transfer_ctx, rebate_amount)?;

    // ── Mark claimed ──
    let claim = &mut ctx.accounts.rebate_claim;
    claim.claimed = true;
    claim.claimed_amount = rebate_amount;

    // ── Update config totals ──
    let config = &mut ctx.accounts.config;
    config.total_rebates_paid = config
        .total_rebates_paid
        .checked_add(rebate_amount)
        .unwrap();

    msg!(
        "Claimed {} $DTOUR rebate for {} anchored receipts",
        rebate_amount,
        claim.anchored_receipts
    );
    Ok(())
}
