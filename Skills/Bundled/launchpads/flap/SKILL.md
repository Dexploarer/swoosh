---
name: flap-launchpad
description: Use Flap for BNB Chain token trading, wallet and bot integrations, token-launcher flows, VaultPortal launches, deployed contract references, and Blink-style surfaces.
category: research
tags:
  - flap
  - bnb-chain
  - evm
  - launchpad
  - token-launch
  - blinks
triggers:
  - Flap
  - flap.sh
  - launch through VaultPortal
  - trade Flap token
  - BNB launchpad
platforms:
  - macOS
  - linux
requires_toolsets:
  - launchpads
  - evm
---

# Flap Launchpad

Use this skill when the user wants BNB Chain launchpad or trading coverage through Flap, including wallet, terminal, bot, and token-launcher integrations.

## Capability Map

- Use the wallet, terminal, and bot developer quickstart for read, quote, and trade integration shape.
- Use the trade-token docs for transaction construction requirements.
- Use the token-launcher quickstart and VaultPortal docs for launch flows.
- Use deployed contract addresses from the Flap docs instead of hardcoding stale addresses in prompts.
- Treat Blink surfaces as presentation/action wrappers over backend quote/build endpoints, not as the source of truth for execution.

## Swoosh Flow

1. Classify the request as docs lookup, trading preparation, contract lookup, launch preparation, or Blink/action surface.
2. Resolve network and contract references from the current Flap docs before building user-facing guidance.
3. For launch flows, gather token metadata, creator wallet, and VaultPortal-specific parameters before requesting wallet approval.
4. For trading, build or deep-link the transaction path and keep signing in the EVM wallet approval flow.
5. Never accept private keys, seed phrases, browser cookies, or custodial credentials.

## References

- Docs home: https://docs.flap.sh/flap
- Deployed contracts: https://docs.flap.sh/flap/developers/deployed-contract-addresses
- Wallet, terminal, bot quickstart: https://docs.flap.sh/flap/developers/wallet-and-terminal-and-bot-developers/a-quick-start-for-wallet-terminal-bot-developers
- Trade tokens: https://docs.flap.sh/flap/developers/wallet-and-terminal-and-bot-developers/trade-tokens
- Token launcher quickstart: <https://docs.flap.sh/flap/developers/token-launcher-developers/quick-start-token-launcher-developers>
- VaultPortal launch: <https://docs.flap.sh/flap/developers/token-launcher-developers/launch-token-through-vaultportal>
