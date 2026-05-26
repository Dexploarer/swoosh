# 03 — Foundation Models

Use Foundation Models for bounded on-device intelligence where available.

## Prefer for

- Summarization of user-selected/local content.
- Structured extraction.
- Classification/tagging.
- Short suggestions and drafts.
- App-data-grounded tool calling.

## Required practices

- Check model availability before use.
- Handle unsupported device, disabled Apple Intelligence, unsupported language/region, context limits, guardrail failures, cancellation, and timeout.
- Use guided generation for structured app output.
- Do not parse free-form prose into state if a typed schema is possible.
- Keep prompts short and static instructions separate from untrusted input.
- Stream long operations into SwiftUI state without blocking the main actor.
- Log only privacy-safe operational metrics.

## Tool calling

- Tool descriptions must be narrow and factual.
- Never expose secrets or unrelated user data in tool output.
- Do not create broad tools like `runShell`, `queryDatabase`, or `performAction`.
- Split tools into specific operations such as `searchNotes`, `createDraftReminder`, `fetchOrderStatus`.
