# Unified Agentic Workspace Design

Date: 2026-05-24
Status: Draft for implementation planning

## Goal

Make Swoosh feel like a modern Apple-native agentic workspace for 2026 and 2027: beautiful, customizable, rearrangeable, mobile-capable, and visibly alive without becoming decorative or incoherent.

The product should feel like one system across Mac and iPhone:

- The Mac app is the flagship operator workspace.
- The iPhone app is the chat-first companion and control surface.
- Ambient Apple surfaces project the same agent state into the OS.
- Customization is concrete: panels, layouts, themes, density, toolbars, menu bar sections, presets, and saved generative surfaces.

## Product Architecture

Swoosh becomes one product with three coordinated layers.

### 1. Dashboard Flagship

The Mac dashboard is the canonical command center. It owns the full workspace mental model:

- Native sidebar for broad areas.
- Rearrangeable workspace canvas.
- Agent shell as the hero control strip.
- Inspector/action rail for selected context.
- Toolbar for modes, search, layout presets, model, voice, approvals, and customization.
- Panels for work, memory, skills, tools, providers, models, wallet, observability, approvals, and custom generative surfaces.

### 2. Agent Shell Everywhere

`AgentShellView` becomes the shared interaction surface across:

- Full dashboard.
- Menu bar popover.
- Voice pill.
- Desktop overlay.
- iPhone chat root.
- Workspace panels.

The shell includes chat, voice state, model selection, reasoning effort, attachments, generative UI, sync state, approvals, and command composition. Host modes can change density and chrome, but the interaction model stays recognizable.

### 3. Ambient Apple Layer

Swoosh should feel integrated with Apple platforms through:

- Menu bar controls.
- Voice pill and bottom voice scene.
- Desktop generative UI overlay.
- Spotlight indexing.
- Focus filters.
- Widgets.
- Live Activities and Dynamic Island on iOS.
- TipKit onboarding.
- Share/import surfaces.
- Shortcuts/App Intents follow-on.
- Spatial/RealityView agent orb where it reflects live state.

These surfaces should expose real agent state or control. Decorative-only Apple effects are secondary.

## Desktop Flagship Layout

The Mac dashboard becomes a three-column command center.

### Left: Native Navigation

Use a native macOS sidebar, not a card-heavy custom rail.

Suggested top-level areas:

- Today
- Agent
- Work
- Knowledge
- Value
- System
- Observe
- App

The sidebar should stay scannable: one symbol, one title, optional short secondary text only where useful.

### Center: Workspace Canvas

The center is a customizable canvas powered by `PanelHost`.

Default composition:

- Hero strip: agent shell.
- Work board.
- Goals and workflows.
- Memory and skills.
- Models and providers.
- Approvals and audit.
- Tools and MCP.
- Wallet and value panels.
- Custom generative surfaces.

Required workspace capabilities:

- Add panel.
- Remove panel.
- Drag reorder.
- Density control.
- Layout reset.
- Save layout preset.
- Restore layout preset.
- Per-surface layouts for dashboard, tray, pill, and iOS.
- Compact layout behavior on iPhone and narrow windows.

Follow-on capabilities:

- Resize panels.
- Pin panels.
- Focus one panel.
- Open panel in a standalone utility window.
- Save agent-generated surfaces as panels.

### Right: Inspector and Action Rail

The inspector turns selection into action without bloating every panel.

It should show:

- Selected panel or object summary.
- Trust and safety state.
- Pending approvals.
- Suggested next actions.
- Recent evidence.
- Related memory.
- Related tools.
- Runtime diagnostics when relevant.

The inspector is contextual. If nothing is selected, it shows workspace readiness, active model, voice status, and high-priority approvals.

## Mobile Layout

The iPhone app should not be a small desktop dashboard.

It stays chat-first:

- `AgentRoot` remains the primary surface.
- The side drawer holds Workspace, Wallet, Connections, Settings, and MCP.
- `WorkspaceScreen` hosts compact `PanelHost` panels.
- Bottom sheets handle secondary choices.
- The liquid voice sphere remains the mobile voice affordance.
- Live Activities expose long-running agent work.

Mobile workspace panels should be shorter, denser, and interaction-first:

- Recent chats.
- Provider status.
- Skills.
- Wallet.
- Approvals.
- Active goals.
- Local model status.
- Voice transcript.

The mobile rule is: chat is the primary action; workspace is glanceable control.

## Visual System

The visual direction is Apple-native, modern, and restrained.

Use:

- Liquid Glass for live or interactive surfaces.
- Native sidebar styling.
- Semantic materials and foreground styles.
- Theme tokens from `ThemeManager`.
- `SwooshNeonTokens` where the app already uses them.
- Motion tied to agent activity, listening, syncing, approvals, and status changes.
- Spatial/orb visuals only where they clarify live agent state.

Avoid:

- Making every panel glow.
- Card-heavy sidebars.
- Decorative effects with no state meaning.
- One-note color palettes.
- Marketing-page composition inside the app.
- Custom controls where native buttons, menus, toolbars, sheets, and inspectors work better.

## Customization Contract

Customization is a first-class product feature, not a settings afterthought.

Users should be able to customize:

- Panel layout per surface.
- Workspace density.
- Toolbar items and order.
- Menu bar sections and order.
- Theme preset and custom theme values.
- Glass intensity and motion preferences where supported.
- Default model and reasoning effort.
- Voice mode and overlay behavior.
- Saved generative surfaces.

Customization should be inspectable and reversible:

- Reset to default.
- Save preset.
- Duplicate preset.
- Apply preset to a surface.
- Export/import layout follow-on.

## Agentic Behavior

The app should feel agentic because the agent can shape surfaces, not because the UI is flashy.

Agent-emitted UI should flow through `SwooshGenerativeUI` and `GenerativeSurfaceHost`.

The agent can:

- Render a surface in the shell.
- Project a surface to the desktop overlay.
- Suggest adding a saved surface to the workspace.
- Populate panels with actionable summaries.
- Request approvals through visible UI.
- Explain why a memory, skill, provider, or tool is being used.

The agent cannot:

- Bypass the component catalog.
- Create arbitrary native views outside the registered surface contract.
- Approve its own human-only actions.
- Hide safety, permission, or audit state behind decorative UI.

## Apple Platform Features

Prioritized platform features:

1. Liquid Glass and native materials across Mac and iOS.
2. Desktop command center with toolbar, sidebar, inspector, menu commands, and keyboard shortcuts.
3. iPhone chat root with compact workspace panels and voice sphere.
4. Menu bar popover and voice pill sharing the same shell model.
5. Desktop overlay for agent-generated UI.
6. Spotlight indexing for sessions, skills, memories, and workflows.
7. Focus filters for layout, toolbar, and menu bar presets.
8. Widgets for status, approvals, active goal, and quick ask.
9. Live Activities for long-running workflows and voice sessions.
10. App Intents/Shortcuts for ask, start workflow, approve, open workspace, and toggle voice mode.

## Data and State Flow

Keep the existing state boundaries:

- `AgentShellModel` owns shared shell state.
- `PanelLayoutStore` owns per-surface panel layout.
- `ThemeManager` owns visual theme state.
- `GenerativeSurfaceHost` owns active agent-emitted surfaces.
- Runtime snapshots feed dashboard status panes.
- iOS uses `SwooshClient` and does not import `SwooshKit`.

The UI should display state from these stores. It should not compute business rules, provider fallback, wallet math, safety policy, or approval semantics in presentation code.

## Error Handling

Failures should be visible and specific:

- Daemon unavailable: show pairing/runtime guidance.
- Provider unavailable: show provider route and next action.
- Local model unavailable: show install/load state.
- Permission denied: show permission name and owning safety surface.
- Generative UI rejected: show safe fallback with the rejected component reason.
- Layout decode failure: offer reset instead of silently replacing the layout.

Avoid silent defaults that make broken pipelines look successful.

## Accessibility and Interaction

Required:

- Keyboard paths for major desktop actions.
- Toolbar and menu equivalents for hidden gestures.
- Accessible labels on icon-only controls.
- Dynamic Type support on iOS where practical.
- Reduced motion support.
- VoiceOver-readable panel titles and status.
- Touch targets sized for iPhone.
- Pointer hover polish on Mac without relying on hover for core actions.

## Verification

Design implementation is not complete until verified visually and technically.

Required checks for each implementation phase:

- `swift build`
- Focused Swift tests for touched non-UI logic.
- macOS app build through XcodeGen/Xcode project where app files change.
- iOS simulator build with `CODE_SIGNING_ALLOWED=NO` where iOS files change.
- Desktop visual inspection of the running Mac app.
- iPhone or simulator visual inspection of chat and workspace.
- Screenshots for desktop and mobile before final handoff.

## Phased Implementation

### Phase 1: Flagship Workspace Spine

Deliver:

- Dashboard center canvas refinements.
- Inspector/action rail.
- Workspace default layout updates.
- Layout preset model.
- Toolbar actions for customize, reset, density, and search.
- Desktop visual pass.
- iOS workspace default layout alignment.

### Phase 2: Agent Shell Polish

Deliver:

- Shell hero treatment.
- Better empty, thinking, streaming, sync, and approval states.
- Unified command composer.
- Voice and attachment polish.
- Host-mode-specific density refinements.
- iOS chat root polish.

### Phase 3: Ambient Apple Layer

Deliver:

- Menu bar alignment with workspace state.
- Voice pill and desktop overlay refinements.
- Spotlight status surfaces.
- Focus preset application.
- Widgets and Live Activities.
- App Intents/Shortcuts.

### Phase 4: Agentic Custom Surfaces

Deliver:

- Save generative surface as panel.
- Surface gallery.
- Surface pinning.
- Agent-suggested layout changes behind explicit approval.
- Catalog-backed action routing from generated UI into tools and approvals.

## Non-Goals

This design does not:

- Replace SwiftUI with a custom UI framework.
- Make iPhone mimic the desktop layout.
- Add production dependencies.
- Change daemon or ActantDB architecture.
- Weaken permission, approval, or audit boundaries.
- Implement arbitrary agent-authored native UI outside `SwooshGenerativeUI`.

## Definition of Done

The design is successful when:

- The Mac app clearly reads as one flagship command center.
- The iPhone app stays fast, chat-first, and visually related to the Mac.
- Users can rearrange, customize, reset, and save meaningful layouts.
- Agent state, safety state, and runtime state are visible without hunting.
- Apple platform features expose real functionality.
- The same core primitives power desktop, mobile, menu bar, voice, and overlay surfaces.
