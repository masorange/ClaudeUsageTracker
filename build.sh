#!/bin/bash

set -e

echo "🔨 Compilando ClaudeUsageTracker..."

SWIFT_FILES="ClaudeUsageTrackerApp.swift ClaudeUsageManager.swift LocalizationManager.swift PricingManager.swift PreferencesManager.swift CurrencyManager.swift LiteLLMManager.swift UpdateManager.swift SettingsView.swift MainView.swift"

# Compilar para ARM64 (Apple Silicon)
echo "  → Compilando para Apple Silicon (arm64)..."
swiftc \
    -target arm64-apple-macos13.0 \
    -framework AppKit \
    -framework SwiftUI \
    -o ClaudeUsageTracker_arm64 \
    $SWIFT_FILES

# Compilar para x86_64 (Intel)
echo "  → Compilando para Intel (x86_64)..."
swiftc \
    -target x86_64-apple-macos13.0 \
    -framework AppKit \
    -framework SwiftUI \
    -o ClaudeUsageTracker_x86_64 \
    $SWIFT_FILES

# Crear binario universal
echo "  → Creando binario universal..."
lipo -create -output ClaudeUsageTracker_binary ClaudeUsageTracker_arm64 ClaudeUsageTracker_x86_64

# Limpiar binarios temporales
rm ClaudeUsageTracker_arm64 ClaudeUsageTracker_x86_64

# Crear estructura de la app
mkdir -p "ClaudeUsageTracker.app/Contents/MacOS"
mkdir -p "ClaudeUsageTracker.app/Contents/Resources"

# Mover el binario
mv ClaudeUsageTracker_binary "ClaudeUsageTracker.app/Contents/MacOS/ClaudeUsageTracker"
chmod +x "ClaudeUsageTracker.app/Contents/MacOS/ClaudeUsageTracker"

# Copiar recursos
cp -r Assets.xcassets "ClaudeUsageTracker.app/Contents/Resources/"

# Crear icono .icns desde el AppIcon.appiconset
if [ -d "Assets.xcassets/AppIcon.appiconset" ]; then
    # Crear iconset temporal
    mkdir -p /tmp/AppIcon.iconset
    cp Assets.xcassets/AppIcon.appiconset/*.png /tmp/AppIcon.iconset/ 2>/dev/null || true
    
    # Convertir a .icns
    if [ -d "/tmp/AppIcon.iconset" ]; then
        iconutil -c icns /tmp/AppIcon.iconset -o "ClaudeUsageTracker.app/Contents/Resources/AppIcon.icns" 2>/dev/null || true
        rm -rf /tmp/AppIcon.iconset
    fi
fi

# Crear Info.plist
cat > "ClaudeUsageTracker.app/Contents/Info.plist" << 'EOF'
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
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.10.0</string>
    <key>CFBundleVersion</key>
    <string>9</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025 Sergio Bañuls</string>
</dict>
</plist>
EOF

echo "✅ App compilada en: ClaudeUsageTracker.app"
echo ""
echo "Para ejecutarla:"
echo "  open ClaudeUsageTracker.app"
