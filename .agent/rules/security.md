# Swoosh Security Rules

- Crypto tools must never accept private keys, seed phrases, or cookies as input.
- `humanOnly` tools cannot be executed by model-origin calls.
- Secrets live in Keychain under service `ai.swoosh.agent`.
- API routes under `/api/*` require the daemon bearer token. If no token is available, the route tree must deny all requests.
- Validate external input at the route or transport boundary, then keep typed internals strict.
