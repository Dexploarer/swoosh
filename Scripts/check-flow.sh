#!/usr/bin/env bash
# Scripts/check-flow.sh — 0.1A Swoosh flow / topology guard for the `plumber` subagent.
#
# WHY THIS EXISTS, AND WHAT IT DOES NOT DO
# ----------------------------------------
# Swoosh is SwiftPM, not a JS/TS monorepo — there is no dependency-cruiser
# here. Most layering is ALREADY enforced at compile time: SwiftPM forbids a
# target from `import`ing a module it doesn't declare in Package.swift, and it
# rejects circular target dependencies at resolve time. So `swift build` IS the
# module-level illegal-import gate AND the module-cycle gate. Treat
# `Package.swift` as the authoritative module graph; this script only covers
# the edges SwiftPM CANNOT express:
#
#   1. iOS isolation — `Apps/SwooshiOS` is an Xcode target. A stray
#      `import SwooshKit` (or any Process/server/daemon module) only fails at
#      the slow Xcode build. This catches it in milliseconds. The macOS-only
#      modules pull in Foundation.Process / Hummingbird / ActantDBSupervisor
#      and break the iOS build (see CLAUDE.md ios-app-imports-swooshclient-only).
#   2. Domain purity — system frameworks (SwiftUI/AppKit/UIKit) are always
#      importable regardless of Package.swift edges, so SwiftPM can't stop the
#      domain/data layers from importing UI. This forbids it.
#
# Exit non-zero on any violation. Green out of the box today (verified). This
# is the gate `plumber` runs POST-FLIGHT for graph-level evidence instead of
# returning UNKNOWN.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

fail=0
note() { printf '  \033[31m✗\033[0m %s\n' "$1"; fail=1; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }

# Match `import Module` / `@_exported import Module` / `import Module.Sub`,
# excluding commented lines. $1 = dir scope, $2 = pipe-separated module list.
violations() {
  local scope="$1" modules="$2"
  [ -d "$scope" ] || return 0
  grep -rnE "^[[:space:]]*(@_exported[[:space:]]+)?import[[:space:]]+(${modules})\b" \
    "$scope" --include="*.swift" 2>/dev/null \
    | grep -vE "^[^:]*:[0-9]+:[[:space:]]*//"
}

echo "─── Swoosh flow check ──────────────────────────────────"
echo "(SwiftPM Package.swift enforces module-graph layering + acyclicity at"
echo " build time; this guards the edges it can't express.)"
echo ""

# ── Rule 1: iOS isolation ────────────────────────────────────────────
# The iOS app must never import macOS-only / daemon-side modules. These
# pull in Foundation.Process, Hummingbird, or ActantDBSupervisor and break
# the iOS build. SwooshKit is the canonical one (CLAUDE.md).
echo "Rule: iOS app imports no macOS-only / daemon module (Apps/SwooshiOS)"
IOS_FORBIDDEN="SwooshKit|SwooshDaemon|SwooshDaemonSupport|SwooshActantBackend|SwooshProcess|SwooshAPI|SwooshProviderBridge"
ios_hits="$(violations "Apps/SwooshiOS" "$IOS_FORBIDDEN")"
if [ -n "$ios_hits" ]; then
  note "iOS imports a forbidden daemon/macOS module:"
  printf '%s\n' "$ios_hits" | sed 's/^/      /'
else
  ok "no forbidden daemon/macOS imports in Apps/SwooshiOS"
fi

# ── Rule 2: domain/data purity ───────────────────────────────────────
# The kernel/domain (SwooshCore), the tool contract + primitives
# (SwooshTools), and the model catalog (SwooshModels) must stay free of UI
# frameworks. SwiftPM can't gate system-framework imports.
echo ""
echo "Rule: domain/data layers import no UI framework (SwooshCore/Tools/Models)"
UI_FRAMEWORKS="SwiftUI|AppKit|UIKit"
domain_hits=""
for scope in Sources/SwooshCore Sources/SwooshTools Sources/SwooshModels; do
  domain_hits+="$(violations "$scope" "$UI_FRAMEWORKS")"$'\n'
done
domain_hits="$(printf '%s' "$domain_hits" | grep -vE '^[[:space:]]*$' || true)"
if [ -n "$domain_hits" ]; then
  note "domain/data layer imports a UI framework:"
  printf '%s\n' "$domain_hits" | sed 's/^/      /'
else
  ok "no UI-framework imports in SwooshCore / SwooshTools / SwooshModels"
fi

# ── Rule 3: domain does not import concrete adapters ─────────────────
# SwooshCore defines ports (e.g. the ModelProvider protocol). It must not
# import the concrete provider/API/server adapters or UI. Most of this is
# already SwiftPM-enforced (no dep edge), but framework imports + intent are
# guarded here so a new Package.swift edge can't quietly invert the flow.
echo ""
echo "Rule: domain (SwooshCore) imports no concrete adapter / server / UI"
CORE_FORBIDDEN="SwooshProviders|SwooshProviderBridge|SwooshAPI|SwooshUI|Hummingbird"
core_hits="$(violations "Sources/SwooshCore" "$CORE_FORBIDDEN")"
if [ -n "$core_hits" ]; then
  note "SwooshCore imports a concrete adapter / server / UI module:"
  printf '%s\n' "$core_hits" | sed 's/^/      /'
else
  ok "SwooshCore imports no concrete adapter / server / UI module"
fi

echo ""
if [ "$fail" -ne 0 ]; then
  printf '─── flow check: \033[31mFAIL\033[0m — fix the edges above (or update the rule\n'
  printf '    in Scripts/check-flow.sh + .claude/topology.md if the lane changed).\n'
  exit 1
fi
printf '─── flow check: \033[32mPASS\033[0m\n'
