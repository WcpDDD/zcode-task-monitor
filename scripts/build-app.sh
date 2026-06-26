#!/usr/bin/env bash
# Builds ZCodeTaskMonitor.app from the Swift package.
# Produces a self-contained .app bundle at dist/ZCodeTaskMonitor.app,
# signed ad-hoc so Gatekeeper is happy on first launch.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ROOT="$ROOT/app"
DIST="$ROOT/dist"
APP_NAME="ZCodeTaskMonitor"
APP_BUNDLE="$DIST/$APP_NAME.app"

echo "==> Building Swift package (release)..."
cd "$APP_ROOT"
swift build -c release 2>&1 | tail -3

BIN="$APP_ROOT/.build/release/$APP_NAME"
if [[ ! -f "$BIN" ]]; then
  echo "ERROR: built binary not found at $BIN" >&2
  exit 1
fi

echo "==> Assembling $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Info.plist — LSUIElement=true keeps it out of the Dock (menu-bar-only).
cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>ZCodeTaskMonitor</string>
  <key>CFBundleIdentifier</key>
  <string>dev.zcode.taskmonitor</string>
  <key>CFBundleName</key>
  <string>ZCode Task Monitor</string>
  <key>CFBundleDisplayName</key>
  <string>ZCode Task Monitor</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>0.1.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSUserNotificationsUsageDescription</key>
  <string>ZCode Task Monitor 通知你任务状态的变化（例如任务进入等待输入）。</string>
</dict>
</plist>
PLIST

# PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "==> Ad-hoc signing..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>&1 | tail -2 || true

echo "==> Verifying..."
codesign --verify --verbose=1 "$APP_BUNDLE" 2>&1 | tail -2 || true

echo
echo "✅ Built: $APP_BUNDLE"
echo "   Test with: open \"$APP_BUNDLE\""
