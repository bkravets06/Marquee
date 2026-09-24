#!/bin/bash
# Smoke-run Marquee in a booted iOS Simulator and capture screenshots.
#
# Usage: scripts/ci-screenshots.sh <simulator-udid> <path/to/Marquee.app> [output-dir]
#
# Requires a Debug build. If TMDB_ACCESS_TOKEN is set in the environment it is
# forwarded to the app (Debug builds read it when the Keychain is empty), so
# Discover and Search render real TMDB content; without it those screens show
# their "Connect to TMDB" state. Fails if the app is not running when a
# screenshot is due, which turns a crash on launch into a CI failure.
set -euo pipefail

UDID="${1:?simulator udid}"
APP="${2:?path to Marquee.app}"
OUT="${3:-screenshots}"
BUNDLE_ID="com.bjkravets.marquee"

mkdir -p "$OUT"

echo "Booting simulator $UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP"

# Clean status bar for presentable screenshots.
xcrun simctl status_bar "$UDID" override \
  --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 || true
xcrun simctl ui "$UDID" appearance light || true

# Forward the token (if any) to the app process.
export SIMCTL_CHILD_TMDB_ACCESS_TOKEN="${TMDB_ACCESS_TOKEN:-}"
if [ -n "${TMDB_ACCESS_TOKEN:-}" ]; then
  echo "TMDB token present: screenshots will include live content."
else
  echo "No TMDB token: Discover and Search will show their connect state."
fi

# shoot <name> <seconds-to-wait> [launch arguments...]
shoot() {
  local name="$1"; shift
  local wait_seconds="$1"; shift
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  sleep 1
  echo "Launching for '$name' with args: $*"
  xcrun simctl launch "$UDID" "$BUNDLE_ID" "$@"
  sleep "$wait_seconds"
  if ! pgrep -f "Marquee.app/Marquee" >/dev/null; then
    echo "::error::Marquee is not running before the '$name' screenshot (did it crash on launch?)"
    xcrun simctl spawn "$UDID" log show --last 2m --predicate 'process == "Marquee"' --style compact 2>/dev/null | tail -n 80 || true
    exit 1
  fi
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png"
  echo "Saved $OUT/$name.png"
}

SKIP_ONBOARDING=(-settings.hasCompletedOnboarding YES)
SEED=(-marquee.seedLibrary YES)

shoot onboarding 6
shoot discover 14 "${SKIP_ONBOARDING[@]}" "${SEED[@]}" -marquee.initialTab discover
shoot library 10 "${SKIP_ONBOARDING[@]}" "${SEED[@]}" -marquee.initialTab library
shoot detail 14 "${SKIP_ONBOARDING[@]}" "${SEED[@]}" -marquee.openSeededItem YES
shoot search 10 "${SKIP_ONBOARDING[@]}" -marquee.initialTab search

xcrun simctl ui "$UDID" appearance dark || true
shoot library-dark 10 "${SKIP_ONBOARDING[@]}" "${SEED[@]}" -marquee.initialTab library
shoot discover-dark 14 "${SKIP_ONBOARDING[@]}" -marquee.initialTab discover

xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl ui "$UDID" appearance light || true
xcrun simctl status_bar "$UDID" clear || true
echo "Screenshots written to $OUT:"
ls -la "$OUT"
