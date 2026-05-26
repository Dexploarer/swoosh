# 06 — Swift Concurrency

New code should be Swift 6-ready and data-race safe.

## Practices

- Use `async/await` and structured concurrency.
- Mark UI-facing observable models `@MainActor` unless isolated otherwise.
- Use actors for mutable shared non-UI state.
- Make DTOs/tool inputs/tool outputs `Sendable`.
- Prefer `Task {}` tied to view/task lifecycle over detached work.
- Avoid blocking the main actor with model calls, file IO, decoding, or network work.
- Propagate cancellation.
- Add timeouts for model/tool/network calls.
- Treat `@unchecked Sendable` as a code smell requiring a comment and review.
