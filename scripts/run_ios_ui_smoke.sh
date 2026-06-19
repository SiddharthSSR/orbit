#!/usr/bin/env bash
#
# Portable local runner for the Orbit iOS mock UI smoke test.
#
# By default it mirrors the CI job: it picks whatever iPhone simulator is
# available on the machine (instead of a hard-coded name), boots it, waits for
# it to be ready, and runs OrbitUITests/OrbitMockLaunchSmokeTests in mock launch
# mode. A specific simulator can be pinned by name or UDID for local debugging.
#
# No backend and no OpenAI key are required — the UI test launches the app with
# `--orbit-ui-tests`, which uses seeded in-process mock clients.
#
# Usage:
#   scripts/run_ios_ui_smoke.sh                          # dynamic selection (default, used by CI)
#   scripts/run_ios_ui_smoke.sh --simulator "iPhone 16 Pro"
#   scripts/run_ios_ui_smoke.sh --udid <SIMULATOR_UDID>
#   scripts/run_ios_ui_smoke.sh --help
#
# Results are written to build/reports/ (gitignored):
#   build/reports/OrbitUITests.xcresult
#   build/reports/orbit-ui-smoke.log

set -euo pipefail

usage() {
  cat <<'EOF'
Run the Orbit iOS mock UI smoke test (OrbitUITests/OrbitMockLaunchSmokeTests).

Usage:
  scripts/run_ios_ui_smoke.sh [options]

Options:
  --simulator <name>   Use the available iPhone simulator with this exact name.
  --udid <udid>        Use the available simulator with this UDID.
  -h, --help           Show this help and exit.

With no options the first available iPhone simulator is selected dynamically
(the same behavior CI uses). --simulator and --udid are mutually exclusive.
No backend or OpenAI key is required.

Examples:
  scripts/run_ios_ui_smoke.sh
  scripts/run_ios_ui_smoke.sh --simulator "iPhone 16 Pro"
  scripts/run_ios_ui_smoke.sh --udid 0A1B2C3D-4E5F-6789-ABCD-EF0123456789
EOF
}

SIMULATOR_ARG=""
UDID_ARG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --simulator)
      [ $# -ge 2 ] || { echo "error: --simulator requires a value." >&2; usage >&2; exit 2; }
      SIMULATOR_ARG="$2"
      shift 2
      ;;
    --simulator=*)
      SIMULATOR_ARG="${1#*=}"
      [ -n "$SIMULATOR_ARG" ] || { echo "error: --simulator requires a value." >&2; usage >&2; exit 2; }
      shift
      ;;
    --udid)
      [ $# -ge 2 ] || { echo "error: --udid requires a value." >&2; usage >&2; exit 2; }
      UDID_ARG="$2"
      shift 2
      ;;
    --udid=*)
      UDID_ARG="${1#*=}"
      [ -n "$UDID_ARG" ] || { echo "error: --udid requires a value." >&2; usage >&2; exit 2; }
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -n "$SIMULATOR_ARG" ] && [ -n "$UDID_ARG" ]; then
  echo "error: pass only one of --simulator or --udid, not both." >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PROJECT="ios/Orbit/Orbit.xcodeproj"
SCHEME="Orbit"
TEST_TARGET="OrbitUITests/OrbitMockLaunchSmokeTests"
REPORTS_DIR="build/reports"
RESULT_BUNDLE="$REPORTS_DIR/OrbitUITests.xcresult"
LOG_FILE="$REPORTS_DIR/orbit-ui-smoke.log"

AVAILABLE="$(xcrun simctl list devices available)"

fail_with_devices() {
  echo "error: $1" >&2
  echo "Available iPhone simulators:" >&2
  printf '%s\n' "$AVAILABLE" | grep -i 'iPhone' >&2 || echo "  (none found)" >&2
  exit 1
}

if [ -n "$UDID_ARG" ]; then
  # Pin by UDID: confirm it is available and capture its name for display.
  SIMULATOR_ID="$UDID_ARG"
  SIMULATOR_NAME="$(printf '%s\n' "$AVAILABLE" | awk -F '[()]' -v udid="$UDID_ARG" '
    { name = $1; gsub(/^[ \t]+|[ \t]+$/, "", name); if ($2 == udid) { print name; exit } }')"
  if [ -z "$SIMULATOR_NAME" ]; then
    fail_with_devices "no available simulator with UDID '$UDID_ARG'."
  fi
elif [ -n "$SIMULATOR_ARG" ]; then
  # Pin by exact name: capture the matching UDID.
  SIMULATOR_NAME="$SIMULATOR_ARG"
  SIMULATOR_ID="$(printf '%s\n' "$AVAILABLE" | awk -F '[()]' -v want="$SIMULATOR_ARG" '
    { name = $1; gsub(/^[ \t]+|[ \t]+$/, "", name); if (name == want) { print $2; exit } }')"
  if [ -z "$SIMULATOR_ID" ]; then
    fail_with_devices "no available simulator named '$SIMULATOR_ARG'."
  fi
else
  # Default: first available iPhone simulator (same approach as CI), so this
  # works regardless of which simulators are installed locally.
  SIMULATOR_NAME="$(printf '%s\n' "$AVAILABLE" | awk -F '[()]' '/iPhone/ { gsub(/^[ \t]+|[ \t]+$/, "", $1); print $1; exit }')"
  SIMULATOR_ID="$(printf '%s\n' "$AVAILABLE" | awk -F '[()]' '/iPhone/ { print $2; exit }')"
  if [ -z "$SIMULATOR_NAME" ] || [ -z "$SIMULATOR_ID" ]; then
    fail_with_devices "no available iPhone simulator found."
  fi
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
