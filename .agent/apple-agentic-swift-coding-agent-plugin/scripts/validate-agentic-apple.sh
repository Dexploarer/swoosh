#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"
echo "== Agentic Apple Validation =="
if grep -R "LanguageModelSession\|SystemLanguageModel\|FoundationModels" -n . --include='*.swift' >/dev/null 2>&1; then
  grep -R "availability\|SystemLanguageModel" -n . --include='*.swift' >/dev/null 2>&1 || echo "WARN: Foundation Models detected but no obvious availability check found."
  grep -R "Tool" -n . --include='*.swift' >/dev/null 2>&1 && echo "INFO: Tool-like code detected; verify typed input/output, permissions, timeouts, cancellation, tests."
fi
if grep -R "AppIntent" -n . --include='*.swift' >/dev/null 2>&1; then
  grep -R "AppShortcutsProvider" -n . --include='*.swift' >/dev/null 2>&1 || echo "INFO: AppIntents found; consider AppShortcutsProvider for high-value actions."
fi
if find . -iname '*Clip*' -o -iname '*Widget*' | grep -q .; then
  echo "INFO: App Clip/widget-like files found; verify Fruta-style shared code and extension-safe APIs."
fi
exit 0
