#!/usr/bin/env bash
set -euo pipefail
INPUT="$(cat || true)"
# Extract likely build errors from hook payload/output without storing full logs.
echo "$INPUT" | grep -E "(error:|fatal error:|SwiftCompile failed|Command SwiftCompile failed|Testing failed|BUILD FAILED|ARCHIVE FAILED)" | tail -n 40 || true
exit 0
