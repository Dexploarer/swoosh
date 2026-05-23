---
name: add-permission-case
description: Multi-file checklist for adding a new SwooshPermission case. Use when adding a permission, exposing a new capability that needs firewall gating, or wiring a new Scout source / tool family / API surface that requires its own grant. Encodes the enum + profile grants + docs + tool wiring + test path so nothing is forgotten.
---

# Adding a new SwooshPermission case

Permissions are the **only** firewall enforcement surface. Adding one touches 3–5 files and a doc. Skipping any of these is how capabilities end up ungated, ungranted, or invisible to the permission UI.

## Steps

1. **Add the case** to `Sources/SwooshTools/SwooshPermission.swift`. Follow the existing groupings (`// ── <group> ──`) and pick the right one — system, scout personal-data, tool/runtime, files/dev, web/browser, Apple native, workflow, EVM, Solana. New group → new banner comment + brief justification.

   - **Name shape**: `camelCase`, suffix with the verb (`fooRead`, `fooWrite`, `fooRun`, `fooExecute`). Don't rename existing cases — the raw string is the on-disk grant key.
   - **One case per real privilege.** A read/write split (`fooRead` + `fooWrite`) is almost always right; a single `foo` lump is almost always wrong.

2. **Document it** in `Docs/PermissionModel.md`. Update at minimum:
   - The relevant Profiles table row (`safe / developer / automation / power / trader / autonomous`) — say which presets grant it. `autonomous` grants everything; the question is which lower preset does.
   - If the permission gates a Scout source or personal-data capability, add a one-line entry under the appropriate section explaining the trust contract (raw access vs. derived memory).

3. **Add the preset grants** in `Sources/SwooshConfig/PermissionProfile.swift`. Each preset case (`.safe`, `.developer`, `.automation`, `.power`, `.trader`, `.autonomous`, `.custom`) has a switch arm that returns the granted set. Add the new case to every preset that should grant it. `.autonomous` grants every permission — verify the iteration there covers your new case (most use `CaseIterable.allCases`, so this is automatic, but check).

4. **Wire it into the tool / feature**. The tool declares `static let permission: SwooshPermission = .yourNewCase` and the dispatcher (or the tool itself) calls `firewall.require(.yourNewCase)`. Verify both:
   - `grep -n "permission: SwooshPermission" Sources/SwooshToolsets/*Tools.swift` for the tool.
   - `grep -rn "firewall.require(.yourNewCase)\|require(\.yourNewCase)" Sources/` to confirm an actual enforcement site exists.

5. **For Scout sources**, also wire `checkPermission` / `requestPermission` in the source struct under `Sources/SwooshScout/`. Sources without a matching permission case will silently skip at scan time — they need both ends.

6. **Write a test** that asserts the firewall denies the new permission by default and grants it after `grantAll([.yourNewCase])`. Put it in `Tests/SwooshFirewallTests/` or alongside the tool's test file. Existing examples: any `*Tests.swift` with a `XCTAssertThrowsError` against `FirewallError.denied`.

7. **Verify:**
   ```bash
   swift build
   swift test --filter SwooshFirewallTests
   swift test --filter SwooshToolsetsTests   # if you wired to a tool
   swift test --filter SwooshConfigTests     # if you touched preset grants
   ```

## Audit checklist (skim before committing)

- [ ] Case name is `camelCase` with a verb suffix.
- [ ] Placed in the right `// ── <group> ──` section.
- [ ] `Docs/PermissionModel.md` lists it under the relevant profile(s).
- [ ] At least one preset besides `.autonomous` grants it (or it's deliberately autonomous-only — note that in the doc).
- [ ] Exactly one `firewall.require(.newCase)` enforcement site exists, on the actual privilege path.
- [ ] If it gates personal data (Scout source), it's wired through `checkPermission` / `requestPermission` AND mentioned in the privacy/trust note in `Docs/PermissionModel.md`.
- [ ] Test covers both the deny path (no grant → throws) and grant path (granted → passes).
- [ ] The matching tool's `static let permission` references it.

## Pitfalls

- **Case in the enum, not in the doc.** Compiles, ships, gets reviewed, and now the permission is undocumented forever. The safety-banner hook reminds you of this — don't ignore it.
- **Granted by `.autonomous` only.** If no other preset grants it, the capability is effectively unreachable for normal users. Either grant it in `.developer` / `.automation` / `.power` as appropriate, or document the autonomous-only design choice.
- **Case added but no `firewall.require` site.** The permission exists in the type system but the privilege isn't actually gated. Grep for the enforcement site before declaring done.
- **Renaming an existing case.** Breaks every persisted grant set in `~/.swoosh/`. Don't. Add a new case + migrate.
- **Lump permissions.** `notesAccess` covering both read and write is wrong — Scout treats them differently and so should profiles. Split into `notesRead` + `notesWrite`.

## Related

- For adding a new tool that consumes a permission, also use [add-swoosh-tool](../add-swoosh-tool/SKILL.md).
- For the broader safety rules around the firewall, see [swoosh-safety-gates](../swoosh-safety-gates/SKILL.md).
