#!/usr/bin/env bash
#
# Generate an lcov coverage report for the Swoosh SwiftPM test suite, and
# optionally upload it to Codacy.
#
# Usage:
#   Scripts/coverage.sh                 # generate coverage.lcov only
#   CODACY_UPLOAD=1 Scripts/coverage.sh # generate and upload to Codacy
#
# Required env when uploading:
#   CODACY_PROJECT_TOKEN  Repository API token from
#                         https://app.codacy.com/.../coverage/coverage-reporter
#                         NEVER commit this — set it locally in your shell or as
#                         a GitHub Actions secret.

set -euo pipefail

cd "$(dirname "$0")/.."

# --- 1. Run the test suite with coverage instrumentation ------------------
echo "==> swift test --enable-code-coverage"
swift test --enable-code-coverage

# --- 2. Resolve coverage artifact paths -----------------------------------
# `swift test --show-codecov-path` returns the codecov JSON path; the merged
# .profdata file sits alongside it as `default.profdata`.
CODECOV_JSON="$(swift test --show-codecov-path)"
CODECOV_DIR="$(dirname "$CODECOV_JSON")"
PROFDATA="${CODECOV_DIR}/default.profdata"

if [[ ! -f "$PROFDATA" ]]; then
  echo "ERROR: profdata not found at $PROFDATA" >&2
  exit 1
fi

BIN_DIR="$(swift build --show-bin-path)"

# Locate the test binary. On macOS the xctest is a bundle directory; on Linux
# it's a single executable file.
if [[ "$(uname -s)" == "Darwin" ]]; then
  XCTEST_BUNDLE="$(find "$BIN_DIR" -maxdepth 1 -name '*.xctest' -type d | head -n1)"
  BUNDLE_NAME="$(basename "${XCTEST_BUNDLE%.xctest}")"
  TEST_BINARY="${XCTEST_BUNDLE}/Contents/MacOS/${BUNDLE_NAME}"
  LLVM_COV=(xcrun llvm-cov)
else
  TEST_BINARY="$(find "$BIN_DIR" -maxdepth 1 -name '*.xctest' -type f | head -n1)"
  LLVM_COV=(llvm-cov)
fi

if [[ ! -x "$TEST_BINARY" ]]; then
  echo "ERROR: test binary not found or not executable: $TEST_BINARY" >&2
  exit 1
fi

# --- 3. Convert profdata -> lcov ------------------------------------------
# Ignore vendored deps, build outputs, and the test sources themselves.
echo "==> llvm-cov export (lcov)"
"${LLVM_COV[@]}" export \
  -format=lcov \
  -instr-profile="$PROFDATA" \
  -ignore-filename-regex='(^|/)(\.build|Tests|checkouts|DerivedData)/' \
  "$TEST_BINARY" > coverage.lcov

LINES="$(wc -l < coverage.lcov | tr -d ' ')"
echo "==> wrote coverage.lcov (${LINES} lines)"

# --- 4. Optionally upload to Codacy ---------------------------------------
if [[ "${CODACY_UPLOAD:-0}" != "1" ]]; then
  echo "==> skipping upload (set CODACY_UPLOAD=1 to upload to Codacy)"
  exit 0
fi

if [[ -z "${CODACY_PROJECT_TOKEN:-}" ]]; then
  echo "ERROR: CODACY_PROJECT_TOKEN must be set when CODACY_UPLOAD=1" >&2
  exit 1
fi

echo "==> uploading to Codacy"
# Codacy's recommended one-liner pipes a remote script into bash. We pin
# nothing here, so be aware this trusts coverage.codacy.com on every run.
# For a pinned alternative see https://github.com/codacy/codacy-coverage-reporter
bash <(curl -Ls https://coverage.codacy.com/get.sh) report \
  --language Swift \
  --coverage-reports coverage.lcov \
  --force-coverage-parser lcov
