// instructions/unstake.rs — Withdraw $DTOUR after cooldown.
//
// Enforces: now - last_activity_at >= unstake_cooldown_seconds

use anchor_lang::prelude::*;
use anchor_spl::token::{self, Token, TokenAccount, Transfer};

use crate::errors::DtourError;
use crate::state::{ProtocolConfig, StakeAccount};

#[derive(Accounts)]
pub struct Unstake<'info> {
    /// Wallet withdrawing tokens.
    #[account(mut)]
    pub wallet: Signer<'info>,

    /// Protocol config (read for cooldown).
    #[account(
        mut,
        seeds = [b"config"],
        bump = config.bump,
    )]
    pub config: Account<'info, ProtocolConfig>,

    /// Stake account PDA.
    #[account(
        mut,
        seeds = [b"stake", wallet.key().as_ref(), &[stake_account.toolset_index]],
        bump = stake_account.bump,
        has_one = wallet,
    )]
    pub stake_account: Account<'info, StakeAccount>,

    /// PDA-owned vault holding the staked tokens.
    #[account(
        mut,
        address = stake_account.vault,
    )]
    pub stake_vault: Account<'info, TokenAccount>,

    /// Wallet's token account (destination).
    #[account(mut)]
    pub wallet_token_account: Account<'info, TokenAccount>,

    pub token_program: Program<'info, Token>,
}

pub fn handler(ctx: Context<Unstake>, amount: u64) -> Result<()> {
    let stake = &ctx.accounts.stake_account;
    let config = &ctx.accounts.config;
    let clock = Clock::get()?;
    let now = clock.unix_timestamp;

    // ── Cooldown check ──
    let elapsed = now.saturating_sub(stake.last_activity_at);
    require!(
        elapsed >= config.unstake_cooldown_seconds,
        DtourError::CooldownNotElapsed
    );

    // ── Balance check ──
    require!(amount <= stake.amount, DtourError::InsufficientStakeBalance);

    // ── Transfer from vault → wallet (PDA signer) ──
    let wallet_key = ctx.accounts.wallet.key();
    let toolset_slice = [stake.toolset_index];
    let bump_slice = [stake.bump];
    let seeds: &[&[u8]] = &[b"stake", wallet_key.as_ref(), &toolset_slice, &bump_slice];
    let signer_seeds = &[seeds];

    let transfer_ctx = CpiContext::new_with_signer(
        ctx.accounts.token_program.to_account_info(),
        Transfer {
            from: ctx.accounts.stake_vault.to_account_info(),
            to: ctx.accounts.wallet_token_account.to_account_info(),
            authority: ctx.accounts.stake_account.to_account_info(),
        },
        signer_seeds,
    );
    token::transfer(transfer_ctx, amount)?;

    // ── Update stake account ──
    let stake = &mut ctx.accounts.stake_account;
    stake.amount = stake.amount.checked_sub(amount).unwrap();

    // ── Update config totals ──
    let config = &mut ctx.accounts.config;
    config.total_staked = config.total_staked.saturating_sub(amount);

    msg!("Unstaked {} $DTOUR from toolset {}", amount, stake.toolset_index);
    Ok(())
}
