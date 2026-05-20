---
name: Review Current Branch
description: Walk the user through the diff of their current branch, surface risks, and draft review notes
category: coding
tags: [review, git, swift]
trust: promoted
platforms: [macOS, linux]
triggers: ["review my branch", "look at the diff", "review the PR"]
---

## When to use

The user wants a structured second-pass on the work they have in their
current git branch — before they merge, push, or open a PR. Use this
whenever the request mentions "review," "diff," "PR," or "before I ship."

## Procedure

1. Run `git status` and `git diff --stat` against the branch's merge base
   with `main` (`git merge-base HEAD main`). Note added/removed/changed
   files, but do not summarise them yet.
2. For each changed file, read the full content, not just the diff. The
   diff hides surrounding context that is often where bugs hide.
3. Group changes into one of: *feature*, *refactor*, *bug fix*, *test*,
   *docs*, *config*. Be explicit about which group each file falls into.
4. For each feature/refactor/bug-fix group, write three things:
   - **What changed** — one sentence.
   - **Why it might be wrong** — at least one plausible failure mode.
   - **What's tested** — yes/no/partial.
5. Surface risks proactively: missing error handling, untested edge
   cases, type-erased casts, mutable shared state crossing an actor
   boundary, secret literals.
6. End with a "ship?" verdict (`yes`, `yes-with-followups`, `no`) and
   the smallest concrete change that would change the verdict.

## Pitfalls

- Do not skim diffs — read whole files. Drive-by diff review is how
  cross-file bugs slip through.
- Do not propose changes unless the user asks. The output is a review,
  not a refactor.
- If the branch has more than ~30 changed files, ask the user which
  subsystem to focus on first instead of trying to cover everything.
- Avoid commenting on style unless it actually causes a readability or
  safety problem. The user has their own taste.
