# /apple-agent-tool

Implement or review one agent tool for a Swift Apple app.

Requirements:

- Narrow purpose and non-ambiguous name.
- Typed input/output.
- Explicit permissions and read/write classification.
- Timeout and cancellation.
- No secrets or excessive user data in outputs.
- Tests for success, validation, denial, timeout, cancellation, and error mapping.
- If Foundation Models is used, guided generation and availability fallback.
- If action is user-visible/repeatable, consider App Intent exposure.
