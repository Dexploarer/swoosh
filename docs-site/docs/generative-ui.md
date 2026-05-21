---
id: generative-ui
title: Generative UI
sidebar_position: 9
---

# Generative UI (`SwooshGenerativeUI`)

Agent-emitted, native-rendered UI for Swoosh. Mirrors the shape of Google's A2UI v0.9 spec but stays under our control, with SwiftUI rendering today and a clean migration path if A2UI 1.0 or MCP-UI becomes the standard.

## Wire format

A `UISurfaceUpdate` is a flat list of components keyed by ID, with a single designated root:

```json
{
  "surfaceID": "portfolio-snapshot",
  "rootID": "root",
  "version": 1,
  "timestamp": "2026-05-18T12:00:00Z",
  "components": [
    { "id": "root",  "body": { "glassPanel": { "child": "col" } } },
    { "id": "col",   "body": { "column": { "children": ["title","chart"], "spacing": 12 } } },
    { "id": "title", "body": { "heading": { "_0": "Portfolio", "level": 1 } } },
    { "id": "chart", "body": { "chart": {
        "series": [{ "name": "SOL", "values": [1,2,3], "color": null }],
        "kind": "line", "title": "Trend"
    } } }
  ]
}
```

Key properties:

- **Flat addressing.** Children referenced by string ID. Cheap to stream, cheap to diff, cheap to validate.
- **Versioned + timestamped.** Hosts ignore stale updates.
- **Validated.** `surface.validate(against: catalog)` reports missing roots, duplicate IDs, dangling children, and types not in the catalog.

## Component catalog (the security boundary)

Only types in the active `ComponentCatalog` render. Three built-ins:

| Catalog | Use |
|---------|-----|
| `.standard` | Every built-in component (default) |
| `.minimal` | Text + basic layout only. For low-trust agents. |
| `.readOnly` | Standard minus `button`/`link`/`toggle`. For preview-before-approval flows. |

Compose with `.union(_:)` to add custom components; disable specific actions with `.disablingToolCalls()` / `.disablingIntents()`.

Action gating is independent of component allow-listing. `catalog.allows(_ action: UIAction)` decides whether a fired action runs at all.

## Built-in components

30+ built-in component types grouped by category:

| Category | Components |
|----------|-----------|
| **Text** | `text`, `heading`, `caption`, `markdown`, `code` |
| **Layout** | `column`, `row`, `grid`, `stack`, `spacer`, `divider` |
| **Containers** | `card`, `glassPanel`, `section`, `scrollContainer` |
| **Indicators** | `statusChip`, `badge`, `progress`, `meter`, `loadingDots` |
| **Media** | `image`, `avatar` |
| **Interaction** | `button`, `link`, `toggle` |
| **Data** | `list`, `chart`, `keyValue`, `table` |

Each renders via a SwiftUI view in `Builtins.swift`. Theme-aware via the `SwooshTheme` environment.

## Actions

Buttons and toggles fire a `UIAction`:

```swift
enum UIAction {
    case toolCall(name: String, arguments: [String: UIScalar])
    case openURL(String)
    case dispatchIntent(String, payload: [String: UIScalar])
    case setSurface(String, payload: [String: UIScalar])
    case approve(toolCallID: String, scope: String)
    case deny(toolCallID: String, reason: String)
    case noop
}
```

The host's `GenerativeSurfaceHost` (in `SwooshUI/GenerativeSurfaces/`) routes each variant — `toolCall` into the tool registry, `approve`/`deny` into `SwooshFirewall`, `setSurface` to swap rendered surfaces.

## Tool integration

Tools return a `JSONValue` output. A surface is wrapped in the sentinel envelope (`_swoosh_ui` key) so the host can detect it without changing tool interfaces:

```swift
let envelope = try SwooshGenerativeUISentinel.envelope(for: surface)
// → { "_swoosh_ui": { ...surface... } }
```

The host calls `SwooshGenerativeUISentinel.decode(_:)` on every tool output; non-UI outputs return nil and display as JSON.

## Rendering

```swift
import SwooshGenerativeUI
import SwooshUI

@State var host = GenerativeSurfaceHost(catalog: .standard)

GenerativeSurfaceView(host: host, surfaceID: "portfolio-snapshot")
    .swooshThemedBackground()
```

The host accepts surfaces via `host.apply(surface)`; the view re-renders on every version bump. `UIAction`s route through the closure properties on `GenerativeSurfaceHost`.

## Mapping to A2UI v1.0

| A2UI concept | SwooshGenerativeUI equivalent |
|---|---|
| `surfaceUpdate` | `UISurfaceUpdate` |
| `components` array | `components` array |
| Component type (string key) | `UIComponentBody.typeName` |
| Client component registry | `ComponentCatalog` |
| `id` references | `String` IDs |
| Pre-approved component set | `ComponentCatalog.allowedTypes` |

The wire shape isn't byte-identical to A2UI, but the abstraction is — a translation layer maps either way in a few hundred lines.

## Roadmap

- **Streaming partial updates** — current API takes whole-surface updates only.
- **Two-way bound widgets** — propagate state back to the agent (currently one-shot updates).
- **`SwooshUIRendererKit`** — a separate module so non-Swoosh apps can host the renderer without pulling `SwooshCore`.
- **Schema introspection endpoint** — so an agent can ask the host "what's in your catalog?".
