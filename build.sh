#!/bin/bash
set -euo pipefail

VERSION="${VERSION:-2.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-11}"
APP="ClaudeUsageTracker.app"

echo "🔨 Building ClaudeUsageTracker ${VERSION} (universal)..."
swift build -c release --arch arm64 --arch x86_64 --product ClaudeUsageTracker
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ClaudeUsageTracker" "$APP/Contents/MacOS/ClaudeUsageTracker"
chmod +x "$APP/Contents/MacOS/ClaudeUsageTracker"

if [ -d "Assets.xcassets/AppIcon.appiconset" ]; then
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    cp Assets.xcassets/AppIcon.appiconset/*.png "$ICONSET/" 2>/dev/null || true
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null || true
    rm -rf "$(dirname "$ICONSET")"
fi

cat > "$APP/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClaudeUsageTracker</string>
    <key>CFBundleIdentifier</key>
    <string>com.claudeusage.tracker</string>
    <key>CFBundleName</key>
    <string>ClaudeUsageTracker</string>
    <key>CFBundleDisplayName</key>
    <string>Claude Usage Tracker</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025-2026 Sergio Bañuls</string>
</dict>
</plist>
EOF

# Ad-hoc signature so WebKit and SMAppService accept the bundle.
codesign --force --sign - "$APP" >/dev/null

echo "✅ Built $APP ($(lipo -archs "$APP/Contents/MacOS/ClaudeUsageTracker"))"
