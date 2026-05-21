---
id: modules
title: Module Map
sidebar_position: 5
---

# Module Map

Swoosh is sliced into ~54 single-purpose modules in `Sources/`. The dependency hierarchy flows from `SwooshKit` (the public SDK) through `SwooshCore` (the agent kernel) down into the tool, provider, and storage layers.

## Core SDK

| Module | Purpose |
|--------|---------|
| `SwooshKit` | Public SDK — `@_exported import SwooshCore`, exposes `Swoosh.configure { }`. **macOS/Linux only** — pulls in ActantDB supervisor which spawns child processes. |
| `SwooshClient` | Cross-platform client SDK (iOS + macOS). Wire format (`ChatRequest`/`ChatResponse`), `SwooshAPIClient` actor, `TokenStore`/`HostStore`. Zero internal deps. |
| `SwooshCore` | `AgentKernel` actor, `AgentToolLoop`, `PromptBuilder` (the privacy boundary). |
| `SwooshConfig` | Setup graph, credentials, hardware profiling, permissions, doctor checks. |
| `SwooshActantBackend` | Under 100-LoC conformance shim wiring `ActantAgent` into `SwooshCore`'s five protocols. |

## Agent Loop

| Module | Purpose |
|--------|---------|
| `SwooshTools` | Typed `SwooshTool` protocol, `ToolRegistry` actor, `ToolsetID` enum, `TypeErasedTool<T>`. |
| `SwooshToolsets` | Concrete tool implementations: `CoreTools`, `FileTools`, `GitTools`, `JupiterSwapTools`, `HyperliquidTradeTools`, etc. Registered via `DefaultToolRegistrar`. |
| `SwooshFirewall` | **Only** permission enforcement point. `SwooshFirewallActor` denies any permission not explicitly granted. `SwooshAuditLog` is the in-memory audit impl. |
| `SwooshMacros` / `SwooshMacroPlugin` | Compile-time `@SwooshTool` macro infrastructure (swift-syntax 600). |

## Memory & Personalization

| Module | Purpose |
|--------|---------|
| `SwooshScout` | Personalization scanner: source scan → secret redactor → candidate consolidation → `MemoryStore.propose` → user review → approve/reject. |
| `SwooshVault` | Memory review + approved-memory API. |
| `SwooshSecrets` | `KeychainSecretStore` — provider secrets never in plaintext. |

## Workflows & Scheduling

| Module | Purpose |
|--------|---------|
| `SwooshFlow` | Workflow engine: `WorkflowExecutionEngine`, `WorkflowDryRunEngine`, `WorkflowReplayEngine`, `WorkflowTrigger*`. Every workflow is replayable. |
| `SwooshBoard` | Executable multi-agent task graph with typed tasks and replay. |
| `SwooshTriggers` | Trigger + action schema and in-memory registry (firing engine experimental). |
| `SwooshCron` | Scheduled agent job runner. |

## Self-Improvement Pillars

| Module | Purpose |
|--------|---------|
| `SwooshSkills` | Typed `SkillDocument` with `SkillTrust` gate: `draft → reviewed → promoted → frozen`. Only `reviewed`+ entries enter the agent prompt. Tools: `skill_list`, `skill_get`, `skill_search`, `skill_propose`, `skill_approve`. |
| `SwooshGoals` | Typed `Goal` (state: pending/active/paused/completed/abandoned), `GoalRunner` actor with iteration loop. Tools: `goal_set`, `goal_status`, `goal_abandon`. |
| `SwooshManifesting` | Scheduled background pass that mines audit log, drafts skill/memory candidates, writes durable `Manifestation` reports. Nothing auto-applied. Tools: `manifest_now`, `manifest_history`, `manifest_get`. |

## Model Providers

| Module | Purpose |
|--------|---------|
| `SwooshProviders` | Remote adapters: `OpenAIResponsesProvider`, `OpenRouterProvider`, `LocalOpenAICompatibleProvider`, `ElizaCloudProvider`, routed by `ProviderRouter`. |
| `SwooshMLX` | Local Apple-silicon inference via MLXLLM/MLXVLM. Select with `SWOOSH_MLX_MODEL`. |
| `SwooshFoundation` | Apple Foundation Models structured-output adapter. |
| `SwooshModels` | Model catalog + Hugging Face discovery. |

## MCP & Integrations

| Module | Purpose |
|--------|---------|
| `SwooshMCP` | Model Context Protocol — stdio client, JSON-RPC transport, server registry. Agent-facing tools: `mcp.list_servers`, `mcp.list_tools`, `mcp.call`. |
| `SwooshMCPAuth` | Auth helpers for MCP server connections. |
| `SwooshIntegrations` | Third-party integration adapters. |
| `SwooshGateway` | Network gateway and proxy layer. |

## UI

| Module | Purpose |
|--------|---------|
| `SwooshUI` | Dashboard, menu bar, toolbar, theme editor, drag-drop, Inspector, Tips, Spatial (RealityView orb / Model3D), Spotlight indexer, FocusFilter, Live Activities, WritingTools + Image Playground hooks, generative surface host. |
| `SwooshGenerativeUI` | Agent-emitted UI (A2UI-shaped): typed `UIComponent` enum, `UISurfaceUpdate` wire format, `ComponentCatalog` security gate, `UIRenderer` SwiftUI walker. |

## Infrastructure

| Module | Purpose |
|--------|---------|
| `SwooshAPI` | Hummingbird HTTP API server (`swooshd`'s `/api/*` routes). |
| `SwooshDaemon` | `swooshd` entry point; supervises `actantdb` subprocess. |
| `SwooshCLI` | `swift-argument-parser` entry point, all subcommands. |
| `SwooshObservability` | Structured logging, tracing, metrics. |
| `SwooshNetworkPolicy` | Network egress controls. |
| `SwooshSandbox` | Process sandboxing utilities. |
| `SwooshProcess` | Child-process management helpers. |
| `SwooshBench` | Reliability benchmarks (tool validity, memory precision, replay determinism). |
| `SwooshTUI` | Terminal UI primitives for the REPL. |
| `SwooshLSP` | sourcekit-lsp integration. |
| `SwooshDoctor` | System health check implementations. |
| `SwooshInstaller` | Install / update helpers. |
| `SwooshChatSDK` | Typed chat message types and session management. |
| `SwooshPlugins` | Plugin host for runtime-loaded extensions. |
| `SwooshMedia` | Media generation tool surface. |
| `SwooshApprovals` | Approval center UI and request routing. |
| `SwooshDaemonSupport` | Shared helpers used by the daemon. |
| `SwooshProviderBridge` | Bridge layer between provider adapters and the kernel. |
