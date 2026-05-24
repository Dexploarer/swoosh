# Unified Agentic Workspace First Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first shippable code slice of the Unified Agentic Workspace: layout presets, a desktop dashboard inspector/action rail, and aligned iOS workspace defaults.

**Architecture:** Extend the existing `PanelLayoutStore` instead of creating a parallel customization system. Keep the dashboard inspector as a focused SwiftUI view inside `SwooshUI`, driven by `DashboardTab`, `DashboardRuntimeSnapshot`, and the current `PanelLayout`.

**Tech Stack:** Swift 6.3, SwiftUI, Observation, Swift Testing, existing SwooshUI panel and dashboard modules.

---

### Task 1: Panel Layout Presets

**Files:**
- Modify: `Sources/SwooshUI/Panels/PanelLayout.swift`
- Modify: `Tests/SwooshUITests/DashboardPaneLogicTests.swift`

- [ ] Add `PanelLayoutPreset` with deterministic preset IDs, surface, title, description, symbol, and ordered `PanelKind` list.
- [ ] Add `makeLayout(surface:)`, `defaultPreset(for:)`, `options(for:)`, and `applyPreset(_:to:)`.
- [ ] Update dashboard and iOS default layouts to come from presets.
- [ ] Add tests for dashboard defaults, iOS defaults, and applying a preset.
- [ ] Run `swift test --filter SwooshUITests`.

### Task 2: Desktop Inspector Rail

**Files:**
- Create: `Sources/SwooshUI/DashboardPanes/DashboardInspectorPane.swift`
- Modify: `Sources/SwooshUI/DashboardView.swift`

- [ ] Add `DashboardInspectorPane` with selected surface summary, runtime metrics, layout controls, and next actions.
- [ ] Wrap `DashboardView` detail content in a center/inspector split.
- [ ] Wire inspector actions to select dashboard tabs, toggle workspace editing, apply presets, and reset the dashboard layout.
- [ ] Keep the sidebar native and leave panel rendering in `PanelHost`.
- [ ] Run `swift build`.

### Task 3: Mobile Workspace Alignment

**Files:**
- Modify: `Sources/SwooshUI/Panels/PanelLayout.swift`
- Modify: `Apps/SwooshiOS/WorkspaceScreen.swift`

- [ ] Include approvals, goals, local model status, and voice transcript in the iOS preset options.
- [ ] Add an iOS workspace preset menu to `WorkspaceScreen`.
- [ ] Keep chat-first mobile behavior unchanged.
- [ ] Run the iOS simulator build with `CODE_SIGNING_ALLOWED=NO`.

### Task 4: Visual Verification and Commit

**Files:**
- Inspect changed app surfaces after builds complete.

- [ ] Run focused tests and build commands.
- [ ] Launch or build enough of the macOS app to visually inspect the dashboard.
- [ ] Verify iOS workspace compiles.
- [ ] Commit implementation changes on the current branch.
