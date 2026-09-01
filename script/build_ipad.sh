#!/usr/bin/env bash
set -euo pipefail

# Keep the repository usable when xcode-select points at CommandLineTools.
# Callers may override this for a different installed Xcode release.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR

PROJECT="$ROOT_DIR/apps/ipad/TouchCode.xcodeproj"
SCHEME="${TOUCHCODE_XCODE_SCHEME:-TouchCode}"

if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
  echo "Xcode toolchain not found at $DEVELOPER_DIR" >&2
  echo "Set DEVELOPER_DIR to an installed Xcode Contents/Developer directory." >&2
  exit 1
fi

if [[ -n "${TOUCHCODE_XCODE_DESTINATION:-}" ]]; then
  DESTINATION="$TOUCHCODE_XCODE_DESTINATION"
else
  # Prefer the documented device, then fall back to another available iPad.
  DEVICES="$(xcrun simctl list devices available 2>/dev/null || true)"
  DEVICE_ID=""
  for DEVICE_NAME in "iPad Pro 13-inch (M5)" "iPad Pro 11-inch (M5)"; do
    DEVICE_ID="$(printf '%s\n' "$DEVICES" | grep -m1 "$DEVICE_NAME" | sed -E 's/.*([0-9A-Fa-f]{8}-[0-9A-Fa-f-]{27}).*/\1/' || true)"
    [[ -n "$DEVICE_ID" ]] && break
  done
  if [[ -z "$DEVICE_ID" ]]; then
    DEVICE_ID="$(printf '%s\n' "$DEVICES" | grep -m1 -E 'iPad .*\([0-9A-Fa-f]{8}-[0-9A-Fa-f-]{27}\)' | sed -E 's/.*([0-9A-Fa-f]{8}-[0-9A-Fa-f-]{27}).*/\1/' || true)"
  fi
  if [[ -z "$DEVICE_ID" ]]; then
    echo "No available iPad Simulator found for Xcode at $DEVELOPER_DIR" >&2
    echo "Set TOUCHCODE_XCODE_DESTINATION to an available iPad simulator destination." >&2
    exit 1
  fi
  DESTINATION="platform=iOS Simulator,id=$DEVICE_ID"
fi

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "$DESTINATION" \
  -derivedDataPath "$ROOT_DIR/DerivedData/TouchCode-iPad" \
  CODE_SIGNING_ALLOWED=NO \
  build
