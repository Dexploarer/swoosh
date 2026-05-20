# Swoosh Architecture Rules

- `SwooshKit` is the public Mac/Linux SDK. The iPhone imports `SwooshClient`, not `SwooshKit`.
- Durable agent state goes through ActantDB via `SwooshActantBackend`, `ActantDB`, and `ActantAgent`.
- `PromptBuilder` is the privacy boundary. Raw Scout records, secrets, cookies, rejected memories, and browser history never enter prompts.
- `SwooshFirewall` is the permission enforcement point. Tools must not bypass it.
- Business logic belongs in core, use-case, domain, or tool modules. UI displays state and forwards actions.
