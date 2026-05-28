// instructions/stake.rs — Deposit $DTOUR to stake for a toolset.
//
// Flow:
//   1. Validate toolset_index (0–4)
//   2. Compute protocol fee (amount * protocol_fee_bps / 10_000)
//   3. Transfer fee portion → treasury
//   4. Transfer remaining → stake vault (PDA-owned token account)
//   5. Update StakeAccount.amount and timestamps

use anchor_lang::prelude::*;
use anchor_spl::associated_token::AssociatedToken;
use anchor_spl::token::{self, Mint, Token, TokenAccount, Transfer};

use crate::errors::DtourError;
use crate::state::{ProtocolConfig, StakeAccount, TOOLSET_COUNT};

#[derive(Accounts)]
#[instruction(amount: u64, toolset_index: u8)]
pub struct Stake<'info> {
    /// Wallet staking tokens.
    #[account(mut)]
    pub wallet: Signer<'info>,

    /// Protocol config (read for fee rate + requirements).
    #[account(
        mut,
        seeds = [b"config"],
        bump = config.bump,
    )]
    pub config: Account<'info, ProtocolConfig>,

    /// $DTOUR mint.
    #[account(address = config.token_mint)]
    pub token_mint: Account<'info, Mint>,

    /// Wallet's $DTOUR token account (source).
    #[account(
        mut,
        associated_token::mint = token_mint,
        associated_token::authority = wallet,
    )]
    pub wallet_token_account: Account<'info, TokenAccount>,

    /// Stake account PDA — created on first stake, updated on top-ups.
    #[account(
        init_if_needed,
        payer = wallet,
        space = StakeAccount::SPACE,
        seeds = [b"stake", wallet.key().as_ref(), &[toolset_index]],
        bump,
    )]
    pub stake_account: Account<'info, StakeAccount>,

    /// PDA-owned vault token account for this stake.
    #[account(
        init_if_needed,
        payer = wallet,
        associated_token::mint = token_mint,
        associated_token::authority = stake_account,
    )]
    pub stake_vault: Account<'info, TokenAccount>,

    /// Treasury token account (receives protocol fee).
    #[account(
        mut,
        address = config.treasury,
    )]
    pub treasury: Account<'info, TokenAccount>,

    pub system_program: Program<'info, System>,
    pub token_program: Program<'info, Token>,
    pub associated_token_program: Program<'info, AssociatedToken>,
}

pub fn handler(ctx: Context<Stake>, amount: u64, toolset_index: u8) -> Result<()> {
    require!(
        (toolset_index as usize) < TOOLSET_COUNT,
        DtourError::InvalidToolsetIndex
    );
    require!(amount > 0, DtourError::InsufficientStake);

    let config = &ctx.accounts.config;
    let clock = Clock::get()?;
    let now = clock.unix_timestamp;

    // ── Compute protocol fee ──
    let fee = amount
        .checked_mul(config.protocol_fee_bps as u64)
        .unwrap()
        .checked_div(10_000)
        .unwrap();
    let net_amount = amount.checked_sub(fee).unwrap();

    // ── Transfer fee → treasury ──
    if fee > 0 {
        let fee_ctx = CpiContext::new(
            ctx.accounts.token_program.to_account_info(),
            Transfer {
                from: ctx.accounts.wallet_token_account.to_account_info(),
                to: ctx.accounts.treasury.to_account_info(),
                authority: ctx.accounts.wallet.to_account_info(),
            },
        );
        token::transfer(fee_ctx, fee)?;
    }

    // ── Transfer net amount → stake vault ──
    let stake_ctx = CpiContext::new(
        ctx.accounts.token_program.to_account_info(),
        Transfer {
            from: ctx.accounts.wallet_token_account.to_account_info(),
            to: ctx.accounts.stake_vault.to_account_info(),
            authority: ctx.accounts.wallet.to_account_info(),
        },
    );
    token::transfer(stake_ctx, net_amount)?;

    // ── Update stake account ──
    let stake = &mut ctx.accounts.stake_account;
    if stake.amount == 0 {
        // First-time init
        stake.wallet = ctx.accounts.wallet.key();
        stake.toolset_index = toolset_index;
        stake.staked_at = now;
        stake.vault = ctx.accounts.stake_vault.key();
        stake.bump = ctx.bumps.stake_account;
    }
    stake.amount = stake.amount.checked_add(net_amount).unwrap();
    stake.last_activity_at = now;

    // ── Update config totals ──
    let config = &mut ctx.accounts.config;
    config.total_staked = config.total_staked.checked_add(net_amount).unwrap();

    msg!(
        "Staked {} $DTOUR for toolset {} (fee: {})",
        net_amount,
        toolset_index,
        fee
    );
    Ok(())
}
