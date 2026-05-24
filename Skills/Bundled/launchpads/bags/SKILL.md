---
name: bags-launchpad
description: Use Bags for Solana token launch planning, agent authentication, launch intent creation, and launch transaction creation through the official Bags API.
category: research
tags:
  - bags
  - solana
  - launchpad
  - token-launch
  - memecoin
triggers:
  - Bags launch
  - bags.fm
  - launch intent
  - create launch transaction
  - launch Solana token with Bags
platforms:
  - macOS
  - linux
requires_toolsets:
  - launchpads
  - solana
---

# Bags Launchpad

Use this skill when the user wants to launch or prepare a Solana token through Bags. Stay aligned with the official Bags API and do not invent alternate transaction builders when Bags provides the launch flow.

## Capability Map

- Use agent authentication as the setup and health-check boundary.
- Use launch intents for user-visible launch drafts, resumable setup, and parameter review.
- Use the create-token-launch-transaction endpoint for the executable launch transaction path.
- Keep Bags launch flows Solana-focused unless the current Bags docs explicitly show another supported network.

## Swoosh Flow

1. Check authentication or health with the Bags auth flow before claiming launch readiness.
2. Collect metadata, creator wallet, ticker, image, social links, and launch configuration into a draft first.
3. Build a launch intent for review when the user is still editing.
4. Only request a launch transaction after the user approves the final configuration.
5. Route signatures through Swoosh Solana wallet approval; never ask for seed phrases or private keys.

## References

- Docs index: <https://docs.bags.fm/llms.txt>
- Launch token guide: <https://docs.bags.fm/how-to-guides/launch-token>
- Agent authentication: https://docs.bags.fm/how-to-guides/agent-authentication
- Create launch intent: https://docs.bags.fm/how-to-guides/create-launch-intent
- Create token launch transaction: <https://docs.bags.fm/api-reference/create-token-launch-transaction>
