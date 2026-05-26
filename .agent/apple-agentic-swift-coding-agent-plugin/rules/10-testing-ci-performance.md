# 10 — Testing, CI, and Performance

## Required test layers

- Swift Testing for pure Swift/domain/tool logic.
- XCTest for app integration and existing test stacks.
- XCUIAutomation for UI flows, permissions, localization, and App Clip/shortcut flows.
- Prompt/tool evals for AI features.
- Snapshot/previews where the project uses them.

## AI eval cases

- Happy path.
- Empty/invalid input.
- Sensitive input minimization.
- Tool permission denied.
- Tool timeout.
- Model unavailable.
- Guardrail/safety rejection.
- Context too large.
- Cancellation.
- Localized input.

## Performance

- Use Instruments for CPU, memory, hangs, launch time, and energy.
- Keep model calls off main actor.
- Budget time and context.
- Add signposts for long-running flows when helpful.
