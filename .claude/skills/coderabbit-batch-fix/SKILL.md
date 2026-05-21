---
name: coderabbit-batch-fix
description: How to triage and apply a batch of CodeRabbit review findings efficiently. Use when the user mentions "coderabbit", "code review findings", "21 findings", "fix the review", or wants to apply a batch of PR review comments. Encodes the severity-first, file-grouped order this repo uses (see recent passes of 21 findings).
---

# CodeRabbit batch-fix pass

This repo has run batched CodeRabbit passes (e.g., 21 findings: 4 critical / 8 major / 9 minor in a single sitting on 2026-05-21). The shape is reliable.

## Order of operations

1. **Pull findings into a list.** If from a PR, use `gh api repos/Dexploarer/swoosh/pulls/<N>/comments`. If from a paste, accept as-is.
2. **Group by file.** Apply all findings in one file before moving on — minimizes re-reads.
3. **Sort by severity within file:** Critical → Major → Minor. Critical fixes can invalidate downstream Major comments on the same lines.
4. **Verify after each file:**
   ```bash
   swift build 2>&1 | tail -5
   swift test --filter <RelevantTests> 2>&1 | grep "Test run"
   ```
5. **Commit per-file or per-area**, not one giant commit. Past passes used messages like `Apply CodeRabbit fixes to CDPSession (4 findings)` — keeps `git log` readable for future review-of-the-review.

## What to skip

- **Style nits that contradict the existing file.** This codebase has a clear style (one-line file-header comment with version tag, terse type docs). If CodeRabbit pushes generic verbose docs, decline.
- **Suggestions to add error handling where the call site is internal-only.** Per the project conventions: only validate at system boundaries (route handlers, CLI input, file/API edges). Don't validate between trusted internal modules.
- **Suggestions to widen `Sendable` containers to `Any`.** Always prefer the concrete type. See the `swift-concurrency-triage` bundled skill in `Skills/Bundled/` for the canonical reasoning.

## What to never skip

- **`humanOnly` boundary regressions** — if CodeRabbit flags that a model-origin path can hit a destructive tool, that's a real issue per engineering rule #8.
- **Secret-in-prompt regressions** — engineering rule #6 is non-negotiable.
- **Firewall bypass paths** — engineering rule #2.

## After the pass

```bash
swift test                                  # full suite
git log --oneline origin/main..HEAD          # review the commit chain
```

Then either push as a follow-up commit chain on the PR branch, or open a new "CodeRabbit fixes" PR if the original is already merged.
