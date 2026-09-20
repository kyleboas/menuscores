#!/bin/bash
# Assembles MenuScores.app from the SwiftPM executable.
# Local build, manual install — no auto-update, no signing identity required.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="build/MenuScores.app"

swift build -c "$CONFIG" --product MenuScoresApp

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/MenuScoresApp" "$APP/Contents/MacOS/MenuScores"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>MenuScores</string>
    <key>CFBundleDisplayName</key>     <string>MenuScores</string>
    <key>CFBundleIdentifier</key>      <string>local.menuscores</string>
    <key>CFBundleExecutable</key>      <string>MenuScores</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.1.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <!-- Menu bar only: no Dock icon, no app switcher entry. -->
    <key>LSUIElement</key>             <true/>
    <key>NSHumanReadableCopyright</key><string>Local build</string>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS will run it and remember network permission.
codesign --force --sign - "$APP" 2>/dev/null || echo "note: ad-hoc signing skipped"

echo "Built $APP"
