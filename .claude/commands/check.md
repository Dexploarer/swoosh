---
description: Quick health check — swift build + targeted swift test on whatever you just changed
---

Run a fast safety check on the current working tree.

Procedure:

1. `git status` to see what's changed.
2. `swift build 2>&1 | tail -20` — make sure it compiles. If errors, stop and report them; don't proceed to tests.
3. Infer the test target(s) from the changed files:
   - `Sources/Swoosh<Foo>/**` → `swift test --filter Swoosh<Foo>Tests`
   - Multiple modules → loop via `for t in ...; do swift test --filter $t ...; done` (don't stack `--filter` flags — they hang).
   - Apps/SwooshiOS/** → don't run swift test; instead build the iOS scheme.
4. Report a tight summary: build pass/fail, tests pass/fail per target, and any obvious next step.

If the changed surface is broad (many modules), ask whether to run full `swift test` (~15s) or just the most relevant 1-2 filters.

Don't commit. Don't push. This is read-only verification.
