// dtour-vault — $DTOUR Vault: staking, buyback+burn, builder rewards, creator rewards
//
// Revenue sources:
//   - Jupiter platformFeeBps (0.1% on every swap)
//   - Eliza Cloud affiliate (20% markup on inference)
//   - Hyperliquid builder code (coming)
//   - Pump.fun creator fees on $DTOUR token
//
// Revenue split (configurable):
//   40% → Vault stakers (pro-rata by weight)
//   25% → Buyback & burn (deflationary pressure)
//   15% → Builder rewards (GitHub-verified contributors)
//   10% → Creator rewards (skill/workflow authors)
//   10% → Treasury (development, infra)
//
// $DTOUR Mint: DijmsEDeTXsWCkCLkhYJNTutKaHf541xZshVrCUbcozy

use anchor_lang::prelude::*;
use anchor_spl::token::{self, Token, TokenAccount, Transfer, Mint, Burn};

declare_id!("11111111111111111111111111111112"); // TODO: solana-keygen grind

// ═══════════════════════════════════════════════════════════════════
// Constants
// ═══════════════════════════════════════════════════════════════════

const MAX_SKILL_IDS: usize = 10;
const MAX_SKILL_ID_LEN: usize = 64;
const MAX_GITHUB_LEN: usize = 39;  // GitHub max username length

const LOCK_FLEX: i64 = 0;
const LOCK_BRONZE: i64 = 30 * 24 * 60 * 60;
const LOCK_SILVER: i64 = 90 * 24 * 60 * 60;
const LOCK_GOLD: i64 = 180 * 24 * 60 * 60;
const LOCK_DIAMOND: i64 = 365 * 24 * 60 * 60;

const MULT_FLEX: u64 = 10000;
const MULT_BRONZE: u64 = 15000;
const MULT_SILVER: u64 = 25000;
const MULT_GOLD: u64 = 40000;
const MULT_DIAMOND: u64 = 70000;

#[program]
pub mod dtour_vault {
    use super::*;

    pub fn initialize(
        ctx: Context<Initialize>,
        vault_share_bps: u16,
        burn_share_bps: u16,
        builder_share_bps: u16,
        creator_share_bps: u16,
        treasury_share_bps: u16,
    ) -> Result<()> {
        let total = vault_share_bps as u32 + burn_share_bps as u32
            + builder_share_bps as u32 + creator_share_bps as u32
            + treasury_share_bps as u32;
        require!(total == 10000, VaultError::InvalidFeeShares);

        let config = &mut ctx.accounts.config;
        config.admin = ctx.accounts.admin.key();
        config.dtour_mint = ctx.accounts.dtour_mint.key();
        config.vault_share_bps = vault_share_bps;
        config.burn_share_bps = burn_share_bps;
        config.builder_share_bps = builder_share_bps;
        config.creator_share_bps = creator_share_bps;
        config.treasury_share_bps = treasury_share_bps;
        config.total_staked = 0;
        config.total_weight = 0;
        config.reward_pool_balance = 0;
        config.builder_pool_balance = 0;
        config.creator_pool_balance = 0;
        config.total_burned = 0;
        config.total_buyback_reserves = 0;
        config.bump = ctx.bumps.config;
        Ok(())
    }

    pub fn vault_deposit(ctx: Context<VaultDeposit>, amount: u64, lock_tier: u8) -> Result<()> {
        require!(amount > 0, VaultError::ZeroAmount);
        let (duration, multiplier) = tier_params(lock_tier)?;

        token::transfer(CpiContext::new(
            ctx.accounts.token_program.to_account_info(),
            Transfer {
                from: ctx.accounts.user_token_account.to_account_info(),
                to: ctx.accounts.vault_token_account.to_account_info(),
                authority: ctx.accounts.owner.to_account_info(),
            },
        ), amount)?;

        let clock = Clock::get()?;
        let vault = &mut ctx.accounts.vault_account;
        let config = &mut ctx.accounts.config;
        let old_weight = vault.weight;

        vault.owner = ctx.accounts.owner.key();
        vault.amount = vault.amount.checked_add(amount).ok_or(VaultError::Overflow)?;
        vault.lock_tier = lock_tier;
        vault.lock_duration = duration;
        vault.deposit_timestamp = clock.unix_timestamp;
        vault.last_claim_timestamp = clock.unix_timestamp;
        vault.weight = bps_mul(vault.amount, multiplier)?;
        vault.bump = ctx.bumps.vault_account;

        config.total_staked = config.total_staked.checked_add(amount).ok_or(VaultError::Overflow)?;
        config.total_weight = config.total_weight
            .checked_sub(old_weight).ok_or(VaultError::Overflow)?
            .checked_add(vault.weight).ok_or(VaultError::Overflow)?;
        Ok(())
    }

    pub fn vault_withdraw(ctx: Context<VaultWithdraw>) -> Result<()> {
        let vault = &ctx.accounts.vault_account;
        let clock = Clock::get()?;
        let unlock = vault.deposit_timestamp.checked_add(vault.lock_duration).ok_or(VaultError::Overflow)?;
        require!(clock.unix_timestamp >= unlock, VaultError::StillLocked);
        let amount = vault.amount;
        require!(amount > 0, VaultError::ZeroAmount);

        let config_key = ctx.accounts.config.key();
        let seeds = &[b"vault_token", config_key.as_ref(), &[ctx.accounts.config.bump]];
        token::transfer(CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            Transfer {
                from: ctx.accounts.vault_token_account.to_account_info(),
                to: ctx.accounts.user_token_account.to_account_info(),
                authority: ctx.accounts.config.to_account_info(),
            },
            &[seeds],
        ), amount)?;

        let config = &mut ctx.accounts.config;
        config.total_staked = config.total_staked.checked_sub(amount).ok_or(VaultError::Overflow)?;
        config.total_weight = config.total_weight.checked_sub(vault.weight).ok_or(VaultError::Overflow)?;
        let vault = &mut ctx.accounts.vault_account;
        vault.amount = 0;
        vault.weight = 0;
        Ok(())
    }

    pub fn vault_claim_rewards(ctx: Context<VaultClaimRewards>) -> Result<()> {
        let vault = &ctx.accounts.vault_account;
        let config = &ctx.accounts.config;
        require!(vault.weight > 0 && config.total_weight > 0 && config.reward_pool_balance > 0, VaultError::NoRewards);

        let reward = (config.reward_pool_balance as u128)
            .checked_mul(vault.weight as u128).ok_or(VaultError::Overflow)?
            .checked_div(config.total_weight as u128).ok_or(VaultError::Overflow)? as u64;
        require!(reward > 0, VaultError::NoRewards);

        let config_key = ctx.accounts.config.key();
        let seeds = &[b"reward_pool", config_key.as_ref(), &[ctx.accounts.config.bump]];
        token::transfer(CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            Transfer {
                from: ctx.accounts.reward_pool_token.to_account_info(),
                to: ctx.accounts.user_token_account.to_account_info(),
                authority: ctx.accounts.config.to_account_info(),
            },
            &[seeds],
        ), reward)?;

        let config = &mut ctx.accounts.config;
        config.reward_pool_balance = config.reward_pool_balance.checked_sub(reward).ok_or(VaultError::Overflow)?;
        let vault = &mut ctx.accounts.vault_account;
        vault.last_claim_timestamp = Clock::get()?.unix_timestamp;
        Ok(())
    }

    // ── 5-way Sweep ──────────────────────────────────────────────
    // Protocol-only: takes collected fees (already $DTOUR) and
    // splits across stakers, burn, builders, creators, treasury.
    pub fn sweep_fees(ctx: Context<SweepFees>, total_amount: u64) -> Result<()> {
        require!(total_amount > 0, VaultError::ZeroAmount);
        let config = &ctx.accounts.config;

        let vault_amt = bps_of(total_amount, config.vault_share_bps)?;
        let burn_amt = bps_of(total_amount, config.burn_share_bps)?;
        let builder_amt = bps_of(total_amount, config.builder_share_bps)?;
        let creator_amt = bps_of(total_amount, config.creator_share_bps)?;
        let treasury_amt = total_amount
            .checked_sub(vault_amt).ok_or(VaultError::Overflow)?
            .checked_sub(burn_amt).ok_or(VaultError::Overflow)?
            .checked_sub(builder_amt).ok_or(VaultError::Overflow)?
            .checked_sub(creator_amt).ok_or(VaultError::Overflow)?;

        // Vault staker rewards
        if vault_amt > 0 {
            token::transfer(CpiContext::new(ctx.accounts.token_program.to_account_info(), Transfer {
                from: ctx.accounts.admin_token_account.to_account_info(),
                to: ctx.accounts.reward_pool_token.to_account_info(),
                authority: ctx.accounts.admin.to_account_info(),
            }), vault_amt)?;
        }
        // BURN — reduces total supply permanently
        if burn_amt > 0 {
            token::burn(CpiContext::new(ctx.accounts.token_program.to_account_info(), Burn {
                mint: ctx.accounts.dtour_mint.to_account_info(),
                from: ctx.accounts.admin_token_account.to_account_info(),
                authority: ctx.accounts.admin.to_account_info(),
            }), burn_amt)?;
        }
        // Builder rewards
        if builder_amt > 0 {
            token::transfer(CpiContext::new(ctx.accounts.token_program.to_account_info(), Transfer {
                from: ctx.accounts.admin_token_account.to_account_info(),
                to: ctx.accounts.builder_pool_token.to_account_info(),
                authority: ctx.accounts.admin.to_account_info(),
            }), builder_amt)?;
        }
        // Creator rewards
        if creator_amt > 0 {
            token::transfer(CpiContext::new(ctx.accounts.token_program.to_account_info(), Transfer {
                from: ctx.accounts.admin_token_account.to_account_info(),
                to: ctx.accounts.creator_pool_token.to_account_info(),
                authority: ctx.accounts.admin.to_account_info(),
            }), creator_amt)?;
        }
        // Treasury
        if treasury_amt > 0 {
            token::transfer(CpiContext::new(ctx.accounts.token_program.to_account_info(), Transfer {
                from: ctx.accounts.admin_token_account.to_account_info(),
                to: ctx.accounts.treasury_token.to_account_info(),
                authority: ctx.accounts.admin.to_account_info(),
            }), treasury_amt)?;
        }

        let config = &mut ctx.accounts.config;
        config.reward_pool_balance = config.reward_pool_balance.checked_add(vault_amt).ok_or(VaultError::Overflow)?;
        config.builder_pool_balance = config.builder_pool_balance.checked_add(builder_amt).ok_or(VaultError::Overflow)?;
        config.creator_pool_balance = config.creator_pool_balance.checked_add(creator_amt).ok_or(VaultError::Overflow)?;
        config.total_burned = config.total_burned.checked_add(burn_amt).ok_or(VaultError::Overflow)?;
        Ok(())
    }

    // ── Buyback deposit (non-burn) ───────────────────────────────
    // Admin buys $DTOUR from market, deposits into reward pool
    pub fn buyback_deposit(ctx: Context<BuybackDeposit>, amount: u64) -> Result<()> {
        require!(amount > 0, VaultError::ZeroAmount);
        token::transfer(CpiContext::new(ctx.accounts.token_program.to_account_info(), Transfer {
            from: ctx.accounts.admin_token_account.to_account_info(),
            to: ctx.accounts.reward_pool_token.to_account_info(),
            authority: ctx.accounts.admin.to_account_info(),
        }), amount)?;
        let config = &mut ctx.accounts.config;
        config.reward_pool_balance = config.reward_pool_balance.checked_add(amount).ok_or(VaultError::Overflow)?;
        config.total_buyback_reserves = config.total_buyback_reserves.checked_add(amount).ok_or(VaultError::Overflow)?;
        Ok(())
    }

    // ═════════════════════════════════════════════════════════════
    // Builder Registration — GitHub-verified contributors
    //
    // Flow:
    //   1. Contributor calls builder_register(github_username)
    //   2. swooshd verifies GitHub: checks Dtour-Stack org for merged PRs
    //   3. Admin calls builder_verify(merged_pr_count) to activate
    //   4. On each PR merge, admin calls builder_attribute_reward
    //   5. Builder calls builder_claim_rewards to withdraw $DTOUR
    // ═════════════════════════════════════════════════════════════

    pub fn builder_register(ctx: Context<BuilderRegister>, github_username: String) -> Result<()> {
        require!(!github_username.is_empty() && github_username.len() <= MAX_GITHUB_LEN, VaultError::GitHubUsernameTooLong);
        let profile = &mut ctx.accounts.builder_profile;
        profile.owner = ctx.accounts.owner.key();
        profile.github_username = github_username;
        profile.verified = false;
        profile.merged_pr_count = 0;
        profile.unclaimed_rewards = 0;
        profile.total_claimed = 0;
        profile.bump = ctx.bumps.builder_profile;
        Ok(())
    }

    pub fn builder_verify(ctx: Context<BuilderVerify>, merged_pr_count: u32) -> Result<()> {
        let profile = &mut ctx.accounts.builder_profile;
        profile.verified = true;
        profile.merged_pr_count = merged_pr_count;
        Ok(())
    }

    pub fn builder_attribute_reward(ctx: Context<BuilderAttributeReward>, new_prs: u32, reward_amount: u64) -> Result<()> {
        let profile = &ctx.accounts.builder_profile;
        require!(profile.verified, VaultError::BuilderNotVerified);
        let profile = &mut ctx.accounts.builder_profile;
        profile.merged_pr_count = profile.merged_pr_count.checked_add(new_prs).ok_or(VaultError::Overflow)?;
        profile.unclaimed_rewards = profile.unclaimed_rewards.checked_add(reward_amount).ok_or(VaultError::Overflow)?;
        Ok(())
    }

    pub fn builder_claim_rewards(ctx: Context<BuilderClaimRewards>) -> Result<()> {
        let profile = &ctx.accounts.builder_profile;
        require!(profile.verified, VaultError::BuilderNotVerified);
        require!(profile.unclaimed_rewards > 0, VaultError::NoRewards);
        let amount = profile.unclaimed_rewards;

        let config_key = ctx.accounts.config.key();
        let seeds = &[b"builder_pool", config_key.as_ref(), &[ctx.accounts.config.bump]];
        token::transfer(CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            Transfer {
                from: ctx.accounts.builder_pool_token.to_account_info(),
                to: ctx.accounts.user_token_account.to_account_info(),
                authority: ctx.accounts.config.to_account_info(),
            },
            &[seeds],
        ), amount)?;

        let config = &mut ctx.accounts.config;
        config.builder_pool_balance = config.builder_pool_balance.checked_sub(amount).ok_or(VaultError::Overflow)?;
        let profile = &mut ctx.accounts.builder_profile;
        profile.unclaimed_rewards = 0;
        profile.total_claimed = profile.total_claimed.checked_add(amount).ok_or(VaultError::Overflow)?;
        Ok(())
    }

    // ═════════════════════════════════════════════════════════════
    // Creator rewards (skill/workflow authors)
    // ═════════════════════════════════════════════════════════════

    pub fn creator_register(ctx: Context<CreatorRegister>, skill_id: String) -> Result<()> {
        require!(skill_id.len() <= MAX_SKILL_ID_LEN, VaultError::SkillIdTooLong);
        let profile = &mut ctx.accounts.creator_profile;
        if profile.owner == Pubkey::default() {
            profile.owner = ctx.accounts.owner.key();
            profile.total_attributed_volume = 0;
            profile.unclaimed_rewards = 0;
            profile.bump = ctx.bumps.creator_profile;
        }
        require!(profile.skill_ids.len() < MAX_SKILL_IDS, VaultError::TooManySkills);
        require!(!profile.skill_ids.iter().any(|s| s == &skill_id), VaultError::SkillAlreadyRegistered);
        profile.skill_ids.push(skill_id);
        Ok(())
    }

    pub fn creator_claim_rewards(ctx: Context<CreatorClaimRewards>) -> Result<()> {
        let profile = &ctx.accounts.creator_profile;
        require!(profile.unclaimed_rewards > 0, VaultError::NoRewards);
        let amount = profile.unclaimed_rewards;

        let config_key = ctx.accounts.config.key();
        let seeds = &[b"creator_pool", config_key.as_ref(), &[ctx.accounts.config.bump]];
        token::transfer(CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            Transfer {
                from: ctx.accounts.creator_pool_token.to_account_info(),
                to: ctx.accounts.user_token_account.to_account_info(),
                authority: ctx.accounts.config.to_account_info(),
            },
            &[seeds],
        ), amount)?;

        let config = &mut ctx.accounts.config;
        config.creator_pool_balance = config.creator_pool_balance.checked_sub(amount).ok_or(VaultError::Overflow)?;
        let profile = &mut ctx.accounts.creator_profile;
        profile.unclaimed_rewards = 0;
        Ok(())
    }

    pub fn attribute_volume(ctx: Context<AttributeVolume>, _skill_id: String, volume_usd: u64, reward_amount: u64) -> Result<()> {
        let profile = &mut ctx.accounts.creator_profile;
        profile.total_attributed_volume = profile.total_attributed_volume.checked_add(volume_usd).ok_or(VaultError::Overflow)?;
        profile.unclaimed_rewards = profile.unclaimed_rewards.checked_add(reward_amount).ok_or(VaultError::Overflow)?;
        Ok(())
    }
}

// ═══════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════

fn tier_params(t: u8) -> Result<(i64, u64)> {
    match t {
        0 => Ok((LOCK_FLEX, MULT_FLEX)),
        1 => Ok((LOCK_BRONZE, MULT_BRONZE)),
        2 => Ok((LOCK_SILVER, MULT_SILVER)),
        3 => Ok((LOCK_GOLD, MULT_GOLD)),
        4 => Ok((LOCK_DIAMOND, MULT_DIAMOND)),
        _ => Err(VaultError::InvalidTier.into()),
    }
}

fn bps_of(amount: u64, bps: u16) -> Result<u64> {
    Ok((amount as u128).checked_mul(bps as u128).ok_or(VaultError::Overflow)?
        .checked_div(10000).ok_or(VaultError::Overflow)? as u64)
}

fn bps_mul(amount: u64, mult: u64) -> Result<u64> {
    Ok((amount as u128).checked_mul(mult as u128).ok_or(VaultError::Overflow)?
        .checked_div(10000).ok_or(VaultError::Overflow)? as u64)
}

// ═══════════════════════════════════════════════════════════════════
// Account Structs
// ═══════════════════════════════════════════════════════════════════

#[account]
pub struct ProtocolConfig {
    pub admin: Pubkey,
    pub dtour_mint: Pubkey,
    pub vault_share_bps: u16,
    pub burn_share_bps: u16,
    pub builder_share_bps: u16,
    pub creator_share_bps: u16,
    pub treasury_share_bps: u16,
    pub total_staked: u64,
    pub total_weight: u64,
    pub reward_pool_balance: u64,
    pub builder_pool_balance: u64,
    pub creator_pool_balance: u64,
    pub total_burned: u64,
    pub total_buyback_reserves: u64,
    pub bump: u8,
}

#[account]
pub struct VaultAccount {
    pub owner: Pubkey,
    pub amount: u64,
    pub lock_tier: u8,
    pub lock_duration: i64,
    pub deposit_timestamp: i64,
    pub last_claim_timestamp: i64,
    pub weight: u64,
    pub bump: u8,
}

#[account]
pub struct BuilderProfile {
    pub owner: Pubkey,
    pub github_username: String,
    pub verified: bool,
    pub merged_pr_count: u32,
    pub unclaimed_rewards: u64,
    pub total_claimed: u64,
    pub bump: u8,
}

#[account]
pub struct CreatorProfile {
    pub owner: Pubkey,
    pub skill_ids: Vec<String>,
    pub total_attributed_volume: u64,
    pub unclaimed_rewards: u64,
    pub bump: u8,
}

// ═══════════════════════════════════════════════════════════════════
// Instruction Contexts
// ═══════════════════════════════════════════════════════════════════

#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(init, payer = admin,
        space = 8 + 32 + 32 + 2 + 2 + 2 + 2 + 2 + 8 + 8 + 8 + 8 + 8 + 8 + 8 + 1,
        seeds = [b"config"], bump)]
    pub config: Account<'info, ProtocolConfig>,
    pub dtour_mint: Account<'info, Mint>,
    #[account(mut)] pub admin: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct VaultDeposit<'info> {
    #[account(mut, seeds = [b"config"], bump = config.bump)]
    pub config: Account<'info, ProtocolConfig>,
    #[account(init_if_needed, payer = owner, space = 8 + 32 + 8 + 1 + 8 + 8 + 8 + 8 + 1,
        seeds = [b"vault", owner.key().as_ref()], bump)]
    pub vault_account: Account<'info, VaultAccount>,
    #[account(mut, constraint = vault_token_account.mint == config.dtour_mint)]
    pub vault_token_account: Account<'info, TokenAccount>,
    #[account(mut, constraint = user_token_account.mint == config.dtour_mint,
              constraint = user_token_account.owner == owner.key())]
    pub user_token_account: Account<'info, TokenAccount>,
    #[account(mut)] pub owner: Signer<'info>,
    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct VaultWithdraw<'info> {
    #[account(mut, seeds = [b"config"], bump = config.bump)]
    pub config: Account<'info, ProtocolConfig>,
    #[account(mut, seeds = [b"vault", owner.key().as_ref()], bump = vault_account.bump, has_one = owner)]
    pub vault_account: Account<'info, VaultAccount>,
    #[account(mut, constraint = vault_token_account.mint == config.dtour_mint)]
    pub vault_token_account: Account<'info, TokenAccount>,
    #[account(mut, constraint = user_token_account.mint == config.dtour_mint,
              constraint = user_token_account.owner == owner.key())]
    pub user_token_account: Account<'info, TokenAccount>,
    pub owner: Signer<'info>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct VaultClaimRewards<'info> {
    #[account(mut, seeds = [b"config"], bump = config.bump)]
    pub config: Account<'info, ProtocolConfig>,
    #[account(mut, seeds = [b"vault", owner.key().as_ref()], bump = vault_account.bump, has_one = owner)]
    pub vault_account: Account<'info, VaultAccount>,
    #[account(mut, constraint = reward_pool_token.mint == config.dtour_mint)]
    pub reward_pool_token: Account<'info, TokenAccount>,
    #[account(mut, constraint = user_token_account.mint == config.dtour_mint,
              constraint = user_token_account.owner == owner.key())]
    pub user_token_account: Account<'info, TokenAccount>,
    pub owner: Signer<'info>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct SweepFees<'info> {
    #[account(mut, seeds = [b"config"], bump = config.bump, has_one = admin)]
    pub config: Account<'info, ProtocolConfig>,
    #[account(mut, constraint = admin_token_account.mint == config.dtour_mint,
              constraint = admin_token_account.owner == admin.key())]
    pub admin_token_account: Account<'info, TokenAccount>,
    #[account(mut)] pub dtour_mint: Account<'info, Mint>,
    #[account(mut, constraint = reward_pool_token.mint == config.dtour_mint)]
    pub reward_pool_token: Account<'info, TokenAccount>,
    #[account(mut, constraint = builder_pool_token.mint == config.dtour_mint)]
    pub builder_pool_token: Account<'info, TokenAccount>,
    #[account(mut, constraint = creator_pool_token.mint == config.dtour_mint)]
    pub creator_pool_token: Account<'info, TokenAccount>,
    #[account(mut, constraint = treasury_token.mint == config.dtour_mint)]
    pub treasury_token: Account<'info, TokenAccount>,
    pub admin: Signer<'info>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct BuybackDeposit<'info> {
    #[account(mut, seeds = [b"config"], bump = config.bump, has_one = admin)]
    pub config: Account<'info, ProtocolConfig>,
    #[account(mut, constraint = admin_token_account.mint == config.dtour_mint,
              constraint = admin_token_account.owner == admin.key())]
    pub admin_token_account: Account<'info, TokenAccount>,
    #[account(mut, constraint = reward_pool_token.mint == config.dtour_mint)]
    pub reward_pool_token: Account<'info, TokenAccount>,
    pub admin: Signer<'info>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct BuilderRegister<'info> {
    #[account(init, payer = owner, space = 8 + 32 + (4 + MAX_GITHUB_LEN) + 1 + 4 + 8 + 8 + 1,
        seeds = [b"builder", owner.key().as_ref()], bump)]
    pub builder_profile: Account<'info, BuilderProfile>,
    #[account(mut)] pub owner: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct BuilderVerify<'info> {
    #[account(seeds = [b"config"], bump = config.bump, has_one = admin)]
    pub config: Account<'info, ProtocolConfig>,
    #[account(mut)] pub builder_profile: Account<'info, BuilderProfile>,
    pub admin: Signer<'info>,
}

#[derive(Accounts)]
pub struct BuilderAttributeReward<'info> {
    #[account(seeds = [b"config"], bump = config.bump, has_one = admin)]
    pub config: Account<'info, ProtocolConfig>,
    #[account(mut)] pub builder_profile: Account<'info, BuilderProfile>,
    pub admin: Signer<'info>,
}

#[derive(Accounts)]
pub struct BuilderClaimRewards<'info> {
    #[account(mut, seeds = [b"config"], bump = config.bump)]
    pub config: Account<'info, ProtocolConfig>,
    #[account(mut, seeds = [b"builder", owner.key().as_ref()], bump = builder_profile.bump, has_one = owner)]
    pub builder_profile: Account<'info, BuilderProfile>,
    #[account(mut, constraint = builder_pool_token.mint == config.dtour_mint)]
    pub builder_pool_token: Account<'info, TokenAccount>,
    #[account(mut, constraint = user_token_account.mint == config.dtour_mint,
              constraint = user_token_account.owner == owner.key())]
    pub user_token_account: Account<'info, TokenAccount>,
    pub owner: Signer<'info>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct CreatorRegister<'info> {
    #[account(init_if_needed, payer = owner,
        space = 8 + 32 + 4 + (MAX_SKILL_IDS * (4 + MAX_SKILL_ID_LEN)) + 8 + 8 + 1,
        seeds = [b"creator", owner.key().as_ref()], bump)]
    pub creator_profile: Account<'info, CreatorProfile>,
    #[account(mut)] pub owner: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct CreatorClaimRewards<'info> {
    #[account(mut, seeds = [b"config"], bump = config.bump)]
    pub config: Account<'info, ProtocolConfig>,
    #[account(mut, seeds = [b"creator", owner.key().as_ref()], bump = creator_profile.bump, has_one = owner)]
    pub creator_profile: Account<'info, CreatorProfile>,
    #[account(mut, constraint = creator_pool_token.mint == config.dtour_mint)]
    pub creator_pool_token: Account<'info, TokenAccount>,
    #[account(mut, constraint = user_token_account.mint == config.dtour_mint,
              constraint = user_token_account.owner == owner.key())]
    pub user_token_account: Account<'info, TokenAccount>,
    pub owner: Signer<'info>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct AttributeVolume<'info> {
    #[account(seeds = [b"config"], bump = config.bump, has_one = admin)]
    pub config: Account<'info, ProtocolConfig>,
    #[account(mut)] pub creator_profile: Account<'info, CreatorProfile>,
    pub admin: Signer<'info>,
}

// ═══════════════════════════════════════════════════════════════════
// Errors
// ═══════════════════════════════════════════════════════════════════

#[error_code]
pub enum VaultError {
    #[msg("Fee shares must sum to 10000 bps")] InvalidFeeShares,
    #[msg("Invalid lock tier (0-4)")] InvalidTier,
    #[msg("Amount must be > 0")] ZeroAmount,
    #[msg("Vault still locked")] StillLocked,
    #[msg("No rewards to claim")] NoRewards,
    #[msg("Arithmetic overflow")] Overflow,
    #[msg("Skill ID too long (max 64)")] SkillIdTooLong,
    #[msg("Max 10 skills per creator")] TooManySkills,
    #[msg("Skill already registered")] SkillAlreadyRegistered,
    #[msg("GitHub username invalid (1-39 chars)")] GitHubUsernameTooLong,
    #[msg("Builder not verified — admin must verify first")] BuilderNotVerified,
}
