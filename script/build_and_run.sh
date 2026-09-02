#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="TouchCodeMac"
HELPER_NAME="TouchCodeIdentityHelper"
BUNDLE_ID="com.touchcode.mac"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/apps/mac-app"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_HELPERS="$APP_CONTENTS/Helpers"
APP_BINARY="$APP_MACOS/$APP_NAME"
HELPER_BINARY="$APP_HELPERS/$HELPER_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
PNPM_PATH="$(command -v pnpm)"

# SwiftPM's build service must come from a full Xcode installation. Keep this
# command reproducible when the machine's global xcode-select points at the
# standalone CommandLineTools package.
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build --package-path "$PACKAGE_DIR" --build-system native
BUILD_BINARY="$(swift build --package-path "$PACKAGE_DIR" --build-system native --show-bin-path)/$APP_NAME"
BUILD_HELPER="$(swift build --package-path "$PACKAGE_DIR" --build-system native --show-bin-path)/$HELPER_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_HELPERS"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$BUILD_HELPER" "$HELPER_BINARY"
chmod +x "$APP_BINARY"
chmod +x "$HELPER_BINARY"
test -x "$HELPER_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>LSEnvironment</key>
  <dict>
    <key>TOUCHCODE_ROOT</key>
    <string>$ROOT_DIR</string>
    <key>TOUCHCODE_PNPM</key>
    <string>$PNPM_PATH</string>
  </dict>
</dict>
</plist>
PLIST

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
