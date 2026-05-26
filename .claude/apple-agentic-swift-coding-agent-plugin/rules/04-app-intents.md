# 04 — App Intents and System Surfaces

Use App Intents for stable repeatable actions and AppEntity for content the system should understand.

## Good candidates

- Create/search/update a domain object.
- Start a workflow.
- Summarize or classify selected content.
- Query a current app state.
- Trigger widget/control/shortcut actions.

## Practices

- Provide localized titles, descriptions, parameter titles, and result dialogs.
- Keep `perform()` fast, deterministic, cancellable, and safe outside the app process.
- Use `openAppWhenRun` only when full UI is required.
- Add App Shortcuts phrases for high-value actions.
- Use AppEntity display representations and queries for user-owned content.
- Test no-app-open and extension contexts.
