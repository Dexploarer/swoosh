---
name: dtour-token-gating
description: How $DTOUR token gating works — what's free, what requires stake
category: protocol
tags: [dtour, token, stake, launchpad, gating, opt-in]
trust: promoted
platforms: [macOS, iOS]
triggers:
  - dtour
  - token gate
  - stake required
  - launch token
  - launchpad
---

# $DTOUR Token Gating

## Principle: Everything is free except launching tokens

Swoosh is a consumer app. All features work without $DTOUR tokens.
The only actions that require staking $DTOUR are the 4 launchpad
launch tools — the actual "create and deploy a new token" actions.

## What's free (no stake required)

- **All crypto tools** — EVM, Solana, Jupiter, Hyperliquid, Uniswap
  - Swapping, transferring, reading balances, building transactions
- **Launchpad browsing** — `launchpad.list_platforms`, `launchpad.get_platform`
  - View platform docs, capabilities, analytics, integration status
- **All agent features** — chat, memory, skills, goals, scout, workflows
- **All non-crypto tools** — files, git, terminal, swift dev, MCP

## What requires $DTOUR stake

Only these 4 tools have `isTokenGated = true`:

| Tool | Platform | Chain |
|------|----------|-------|
| `launchpad.pumpportal.launch` | PumpPortal | Solana |
| `launchpad.bags.launch` | Bags | Solana |
| `launchpad.flap.launch` | Flap | BNB Chain |
| `launchpad.four_meme.launch` | Four.meme | BNB Chain |

## How it works

1. User connects wallet (optional)
2. User stakes $DTOUR via the on-chain Swoosh Protocol program
3. The `StakeGateActor` checks on-chain stake when a token-gated tool is called
4. If stake is sufficient → tool executes (still needs approval since risk=critical)
5. If insufficient → blocked with "Launching tokens requires $DTOUR stake"

## How it does NOT work

- No wallet required to use the app
- No stake required for any crypto trading/swapping
- No stake required to browse launchpad docs/analytics
- Receipt tracking only activates when a wallet is connected
- Rebates are earned passively — no action needed beyond staking + using crypto tools
