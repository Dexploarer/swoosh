---
name: add-swoosh-tool
description: Multi-file checklist for adding a new SwooshTool. Use when adding a tool, registering a new tool family, exposing a new agent capability, or wiring crypto/file/git/MCP tool implementations. Encodes the registrar + permission + audit + test path so nothing is forgotten.
---

# Adding a new SwooshTool

Tools are typed (`Codable & Sendable` I/O), permissioned (firewall-gated), and audited. Adding one touches 4–6 files. Skipping any of these is how tools end up bypassing the firewall.

## Steps

1. **Implement the tool struct** in the matching toolset file under `Sources/SwooshToolsets/`. Match the existing family file (`CoreTools.swift`, `FileTools.swift`, `GitTools.swift`, `JupiterSwapTools.swift`, `HyperliquidTradeTools.swift`, `EVMTools.swift`, `SolanaTools.swift`, `UniswapTools.swift`, `MCPTools.swift`, etc.). New family → new file + a `ToolsetID` case.

2. **Conform to `SwooshTool`** from `Sources/SwooshTools/Tool.swift`. Required statics:
   - `name` — kebab-case, namespaced (`solana_transfer`, not `transfer`).
   - `permission` — a case in `SwooshPermission`. If none fits, add a new case in step 4.
   - `risk` — `.read | .write | .network | .funds`. Be honest — funds means it can move user money.
   - `approval` — `.auto | .humanOnly`. Funds-moving and destructive tools are `.humanOnly`.
   - `toolset` — the `ToolsetID` family.

3. **Define `Input` and `Output`** as `Codable & Sendable` structs. **Never** accept private keys, seed phrases, raw cookies, or session tokens as input — these are flagged as hard violations in `AgentToolLoop.swift`.

4. **Add the permission case** (only if a new one is needed) to `Sources/SwooshTools/SwooshPermission.swift`. Then document it in `Docs/PermissionModel.md` (the docs are kept in sync — don't skip this).

5. **Register the tool** in `Sources/SwooshToolsets/Exports.swift`. Find the matching `register<Family>(into:dependencies:)` function and append. A whole new family needs:
   - A new `register<Family>` function in this file.
   - A call site in `DefaultToolRegistrar.registerAll(into:dependencies:selfImprovement:)`.
   - The new case in `ToolsetID`.

6. **Write a unit test** in `Tests/SwooshToolsetsTests/<Family>ToolsTests.swift`. Existing examples cover happy path + one firewall-deny path. Use `MockURLProtocol.swift` for HTTP-touching tools; use the existing fake clients (`URLSessionEVMRPCClient` / `URLSessionSolanaRPCClient` patterns) for RPC-touching tools.

7. **Verify:**
   ```bash
   swift build
   swift test --filter SwooshToolsetsTests
   swift test --filter SwooshFirewallTests
   ```

## Audit checklist (skim before committing)

- [ ] Tool name is namespaced (`<family>_<verb>`).
- [ ] Permission is required, not just declared (`firewall.require(permission)` is called somewhere on the path — usually by the dispatcher; verify your family follows the existing pattern).
- [ ] `humanOnly` if it moves funds, deletes data, sends external messages, or modifies infra.
- [ ] No secrets, keys, or cookies in `Input` fields.
- [ ] Test asserts both the success path and a firewall-deny path.
- [ ] If the tool returns a `UIComponent` envelope, the component type is in `ComponentCatalog`.

## Pitfalls

- **Forgot the registrar.** The tool compiles, tests fail to find it. Always add the `register<Family>` line.
- **Permission case missing from `Docs/PermissionModel.md`.** Easy miss; CI doesn't catch it but code review will.
- **Made a `.write` tool `.auto`.** If the action is reversible by the agent within the same session (e.g., `notes_set`), `.auto` is fine; if it touches the filesystem, network, or chain state, default to `.humanOnly` and let the user downgrade later.
- **New toolset without `ToolsetID` case.** Compiles, but the tool is invisible to the platform-filtering logic that decides iOS-vs-Mac availability.
