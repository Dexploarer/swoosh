// instructions/initialize.rs — Create protocol config and treasury.

use anchor_lang::prelude::*;
use anchor_spl::associated_token::AssociatedToken;
use anchor_spl::token::{Mint, Token, TokenAccount};

use crate::errors::DtourError;
use crate::state::ProtocolConfig;

#[derive(Accounts)]
pub struct Initialize<'info> {
    /// The protocol authority. Pays for account creation.
    #[account(mut)]
    pub authority: Signer<'info>,

    /// $DTOUR token mint.
    pub token_mint: Account<'info, Mint>,

    /// Protocol config PDA — created once.
    #[account(
        init,
        payer = authority,
        space = ProtocolConfig::SPACE,
        seeds = [b"config"],
        bump,
    )]
    pub config: Account<'info, ProtocolConfig>,

    /// Treasury token account — PDA-owned ATA that holds protocol fees
    /// and pays rebates.
    #[account(
        init,
        payer = authority,
        associated_token::mint = token_mint,
        associated_token::authority = config,
    )]
    pub treasury: Account<'info, TokenAccount>,

    pub system_program: Program<'info, System>,
    pub token_program: Program<'info, Token>,
    pub associated_token_program: Program<'info, AssociatedToken>,
}

pub fn handler(
    ctx: Context<Initialize>,
    stake_requirements: [u64; 5],
    rebate_rate_bps: u16,
    protocol_fee_bps: u16,
    unstake_cooldown_seconds: i64,
) -> Result<()> {
    require!(protocol_fee_bps <= 10_000, DtourError::InvalidFeeBps);
    require!(rebate_rate_bps <= 10_000, DtourError::InvalidRebateRate);

    let config = &mut ctx.accounts.config;
    config.authority = ctx.accounts.authority.key();
    config.token_mint = ctx.accounts.token_mint.key();
    config.treasury = ctx.accounts.treasury.key();
    config.stake_requirements = stake_requirements;
    config.rebate_rate_bps = rebate_rate_bps;
    config.protocol_fee_bps = protocol_fee_bps;
    config.unstake_cooldown_seconds = unstake_cooldown_seconds;
    config.total_staked = 0;
    config.total_anchored_batches = 0;
    config.total_rebates_paid = 0;
    config.bump = ctx.bumps.config;

    msg!("Dtour Protocol initialized. Mint: {}", config.token_mint);
    Ok(())
}
