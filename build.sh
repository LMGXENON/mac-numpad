#!/bin/bash
# Builds TouchPad Keypad directly with swiftc (Swift 5 language mode) and
# signs it using Xcode's standard Apple Development certificate for stable
# permissions across rebuilds.
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

# Automatically find Xcode's standard Apple Development certificate
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -o "Apple Development:.*" | head -n 1 | cut -d'"' -f1 || true)

if [ -n "$IDENTITY" ]; then
    echo "Signing with Xcode identity: $IDENTITY"
    codesign --force --timestamp=none --sign "$IDENTITY" "$APP"
else
    echo "(Warning: No Apple Development certificate found — falling back to ad-hoc sign)"
    codesign --force --sign - "$APP"
fi

echo "Built $APP"
echo "Run it with: open $APP"