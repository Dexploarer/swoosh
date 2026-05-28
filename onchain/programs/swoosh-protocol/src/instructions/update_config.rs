// instructions/update_config.rs — Authority-only config updates.

use anchor_lang::prelude::*;

use crate::errors::DtourError;
use crate::state::ProtocolConfig;

#[derive(Accounts)]
pub struct UpdateConfig<'info> {
    /// Must be the current protocol authority.
    pub authority: Signer<'info>,

    /// Protocol config PDA.
    #[account(
        mut,
        seeds = [b"config"],
        bump = config.bump,
        has_one = authority @ DtourError::Unauthorized,
    )]
    pub config: Account<'info, ProtocolConfig>,
}

pub fn handler(
    ctx: Context<UpdateConfig>,
    stake_requirements: Option<[u64; 5]>,
    rebate_rate_bps: Option<u16>,
    protocol_fee_bps: Option<u16>,
    unstake_cooldown_seconds: Option<i64>,
) -> Result<()> {
    let config = &mut ctx.accounts.config;

    if let Some(req) = stake_requirements {
        config.stake_requirements = req;
        msg!("Updated stake requirements");
    }

    if let Some(rate) = rebate_rate_bps {
        require!(rate <= 10_000, DtourError::InvalidRebateRate);
        config.rebate_rate_bps = rate;
        msg!("Updated rebate rate: {} bps", rate);
    }

    if let Some(fee) = protocol_fee_bps {
        require!(fee <= 10_000, DtourError::InvalidFeeBps);
        config.protocol_fee_bps = fee;
        msg!("Updated protocol fee: {} bps", fee);
    }

    if let Some(cooldown) = unstake_cooldown_seconds {
        config.unstake_cooldown_seconds = cooldown;
        msg!("Updated unstake cooldown: {}s", cooldown);
    }

    Ok(())
}
