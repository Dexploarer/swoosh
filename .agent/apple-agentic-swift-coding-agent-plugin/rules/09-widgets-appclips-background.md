# 09 — Widgets, App Clips, Background Work, and Live Activities

## Widgets

- Keep rendering deterministic and fast.
- Use shared App Group data only when needed.
- Use App Intents for interactivity.
- Avoid network/model calls during widget rendering unless explicitly supported and designed.

## App Clips

- Single-purpose, fast, small.
- Share domain logic with full app.
- Avoid heavyweight AI unless the task is essential and availability is handled.
- Promote full app with system UI when the user needs deeper features.

## BackgroundTasks

- Use the API matching the work type.
- Respect system scheduling and cancellation.
- Persist progress safely.
- Do not run hidden AI/network loops.

## Live Activities

- Use only for ongoing, time-sensitive events.
- Keep updates relevant and bounded.
- Provide graceful end states.
