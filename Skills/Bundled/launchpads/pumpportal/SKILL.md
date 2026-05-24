---
name: pumpportal-launchpad
description: Use PumpPortal for Solana token creation, Pump.fun and PumpSwap trading flows, Lightning API execution planning, Local API transaction building, and live data subscriptions.
category: research
tags:
  - pumpportal
  - pumpfun
  - pumpswap
  - solana
  - launchpad
  - memecoin
triggers:
  - PumpPortal
  - Pump.fun launch
  - PumpSwap
  - create Solana memecoin
  - launch token on Solana
platforms:
  - macOS
  - linux
requires_toolsets:
  - launchpads
  - solana
---

# PumpPortal Launchpad

Use this skill when the user wants Solana launchpad coverage through PumpPortal: token creation, Pump.fun buys and sells, PumpSwap buys and sells, or live token/event data.

## Capability Map

- Use the Lightning Transaction API when the user has explicitly configured a PumpPortal API key and wants PumpPortal to execute the trade path.
- Use the Local Transaction API when Swoosh should build unsigned Solana transactions for wallet review, simulation, signature, and broadcast through the normal Solana wallet tools.
- Use PumpPortal data and WebSocket subscriptions for live launch discovery, migration monitoring, and trading context.
- Surface PumpPortal fees, rate limits, and wallet creation docs before proposing an execution path.

## Swoosh Flow

1. Classify the request as data lookup, token creation, local transaction build, or Lightning API execution.
2. For data lookups, prefer read-only PumpPortal docs/data APIs and do not request trading permissions.
3. For local transaction builds, require the user's launch parameters, slippage, priority fee, and wallet destination, then route signing through Swoosh Solana wallet approval.
4. For Lightning API execution, stop unless the user has configured a PumpPortal API key and explicitly approves this faster custody-adjacent path.
5. Never accept seed phrases, private keys, browser cookies, or wallet export material in prompt or tool input.

## References

- Docs home: https://pumpportal.fun/
- Trading API overview: <https://pumpportal.fun/trading-api/>
- Trading API setup: <https://pumpportal.fun/trading-api/setup>
- Fees: <https://pumpportal.fun/fees/>
- Wallet docs: https://pumpportal.fun/create-wallet
