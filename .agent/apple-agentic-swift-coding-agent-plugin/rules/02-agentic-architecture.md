# 02 — Agentic Architecture

Use this default architecture for new agentic features:

```text
SwiftUI/AppIntent/Widget/AppClip boundary
  -> Feature coordinator (@MainActor)
  -> AgentOrchestrator actor/service
  -> Model route + ToolRegistry + SafetyPolicy
  -> Domain services/repositories
  -> Apple frameworks/storage/network
```

## AgentOrchestrator responsibilities

- Check Foundation Models availability.
- Select deterministic fallback or approved model route.
- Keep developer instructions static.
- Attach only task-relevant tools.
- Use typed/guided generation for app state.
- Enforce tool budget, timeout, cancellation, and permission gates.
- Compact context; do not persist full transcript by default.
- Map errors to UI-safe states.

## Tool policy

Every tool must define: purpose, typed input, typed output, read/write class, permissions, timeout, cancellation, error cases, tests, and privacy impact.
