#!/bin/bash
# Builds TouchPad Keypad directly with swiftc (Swift 5 language mode) because the
# installed Command Line Tools' SPM manifest library lacks language-mode settings,
# then assembles a .app bundle so macOS shows a proper "TouchPad Keypad" entry in
# System Settings → Privacy & Security.
set -euo pipefail
cd "$(dirname "$0")"

OUT=".build"
mkdir -p "$OUT"

swiftc \
    -swift-version 5 \
    -O \
    -target arm64-apple-macos13.0 \
    -o "$OUT/TouchPadKeypad" \
    Sources/TouchPadKeypad/*.swift

APP="build/TouchPadKeypad.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$OUT/TouchPadKeypad" "$APP/Contents/MacOS/TouchPadKeypad"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>TouchPadKeypad</string>
    <key>CFBundleIdentifier</key><string>com.touchpadkeypad.mac</string>
    <key>CFBundleName</key><string>TouchPad Keypad</string>
    <key>CFBundleDisplayName</key><string>TouchPad Keypad</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Sign with the stable self-signed identity "TouchPad Keypad Dev" when present:
# macOS TCC keys permissions on the code identity, so a stable identity keeps
# Accessibility/Input Monitoring grants alive across rebuilds (ad-hoc "-" does not).
IDENTITY="TouchPad Keypad Dev"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    codesign --force --timestamp=none --sign "$IDENTITY" "$APP"
else
    codesign --force --sign - "$APP" >/dev/null 2>&1 || true
    echo "(warning: stable identity unavailable — fell back to ad-hoc sign)"
fi
echo "Built $APP"
echo "Run it with: open $APP"
