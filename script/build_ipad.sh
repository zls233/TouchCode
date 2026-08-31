#!/usr/bin/env bash
set -euo pipefail

# Keep the repository usable when xcode-select points at CommandLineTools.
# Callers may override this for a different installed Xcode release.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR

PROJECT="$ROOT_DIR/apps/ipad/TouchCode.xcodeproj"
SCHEME="${TOUCHCODE_XCODE_SCHEME:-TouchCode}"
DESTINATION="${TOUCHCODE_XCODE_DESTINATION:-platform=iOS Simulator,name=iPad Pro 13-inch (M5)}"

if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
  echo "Xcode toolchain not found at $DEVELOPER_DIR" >&2
  echo "Set DEVELOPER_DIR to an installed Xcode Contents/Developer directory." >&2
  exit 1
fi

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "$DESTINATION" \
  -derivedDataPath "$ROOT_DIR/DerivedData/TouchCode-iPad" \
  CODE_SIGNING_ALLOWED=NO \
  build
