---
name: four-meme-launchpad
description: Use Four.meme for BNB Chain meme token launches, protocol integration, TokenManager and helper contract flows, tax-token planning, and PancakeSwap graduation context.
category: research
tags:
  - four-meme
  - bnb-chain
  - evm
  - launchpad
  - token-launch
  - pancakeswap
triggers:
  - Four.meme
  - four meme
  - launch on BNB
  - BNB meme launch
  - tax token launch
platforms:
  - macOS
  - linux
requires_toolsets:
  - launchpads
  - evm
---

# Four.meme Launchpad

Use this skill when the user wants BNB Chain meme token launches or integration guidance through Four.meme.

## Capability Map

- Support the Four.meme launch model: token metadata, creator prebuy, raised token choice, and bonding-curve launch.
- Surface the documented total supply, supported raised/trading tokens, launch cost, trading fee, and graduation to PancakeSwap.
- Use TokenManagerHelper3 as the preferred wrapper when interacting with current and legacy launch contracts.
- For Tax Tokens, explain post-graduation fee settings, allocation splits, dividend minimums, and anti-sniping implications before transaction planning.
- Use the protocol integration docs and ABIs for contract-level work.

## Swoosh Flow

1. Classify the request as launch planning, tax-token planning, protocol integration, contract lookup, or post-graduation analysis.
2. Resolve chain, contract generation, helper contract, raised token, and wallet before producing a transaction plan.
3. For token creation, collect metadata, image URI, socials, creator prebuy amount, and fee/tax parameters if applicable.
4. Route any transaction through EVM wallet approval and the existing mainnet-write safety gates.
5. Never accept private keys, seed phrases, browser cookies, or custodial credentials.

## References

- How it works: https://four-meme.gitbook.io/four.meme/guide/how-it-works
- Tax tokens: https://four-meme.gitbook.io/four.meme/guide/introducing-tax-tokens-on-four.meme
- Protocol integration: https://four-meme.gitbook.io/four.meme/brand/protocol-integration
- API docs: https://1270958763-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FMKYhtLfncF7vyCOOt0Ef%2Fuploads%2F62o7mCRr1omQzpSdmYMW%2FAPI-Documents.03-03-2026.md?alt=media&token=5267cf33-b7de-43fa-a852-5a37e4a5cd8c
