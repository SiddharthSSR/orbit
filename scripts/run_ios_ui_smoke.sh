#!/usr/bin/env bash
#
# Portable local runner for the Orbit iOS mock UI smoke test.
#
# It mirrors the CI job: it picks whatever iPhone simulator is available on the
# machine (instead of a hard-coded name), boots it, waits for it to be ready,
# and runs OrbitUITests/OrbitMockLaunchSmokeTests in mock launch mode.
#
# No backend and no OpenAI key are required — the UI test launches the app with
# `--orbit-ui-tests`, which uses seeded in-process mock clients.
#
# Usage:
#   scripts/run_ios_ui_smoke.sh
#
# Results are written to build/reports/ (gitignored):
#   build/reports/OrbitUITests.xcresult
#   build/reports/orbit-ui-smoke.log

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PROJECT="ios/Orbit/Orbit.xcodeproj"
SCHEME="Orbit"
TEST_TARGET="OrbitUITests/OrbitMockLaunchSmokeTests"
REPORTS_DIR="build/reports"
RESULT_BUNDLE="$REPORTS_DIR/OrbitUITests.xcresult"
LOG_FILE="$REPORTS_DIR/orbit-ui-smoke.log"

# Pick the first available iPhone simulator dynamically (same approach as CI),
# so this works regardless of which simulators are installed locally.
AVAILABLE="$(xcrun simctl list devices available)"
SIMULATOR_NAME="$(printf '%s\n' "$AVAILABLE" | awk -F '[()]' '/iPhone/ { gsub(/^[ \t]+|[ \t]+$/, "", $1); print $1; exit }')"
SIMULATOR_ID="$(printf '%s\n' "$AVAILABLE" | awk -F '[()]' '/iPhone/ { print $2; exit }')"

if [ -z "$SIMULATOR_NAME" ] || [ -z "$SIMULATOR_ID" ]; then
  echo "error: no available iPhone simulator found." >&2
  echo "Install one via Xcode > Settings > Components, then retry. Available devices:" >&2
  printf '%s\n' "$AVAILABLE" >&2
  exit 1
fi

echo "Using simulator: $SIMULATOR_NAME ($SIMULATOR_ID)"

# Boot the simulator if it isn't already, then wait until it is ready.
xcrun simctl boot "$SIMULATOR_ID" || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b

# Start from a clean result bundle so reruns don't fail on a stale path.
mkdir -p "$REPORTS_DIR"
rm -rf "$RESULT_BUNDLE"

echo "Running $TEST_TARGET ..."
set -o pipefail
xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath /tmp/orbit-ui-derived-data \
  -resultBundlePath "$RESULT_BUNDLE" \
  -only-testing:"$TEST_TARGET" \
  2>&1 | tee "$LOG_FILE"

echo "UI smoke passed. Result bundle: $RESULT_BUNDLE"
