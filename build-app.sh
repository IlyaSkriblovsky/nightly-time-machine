#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/build/Nightly Time Machine.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$PWD/build/swift-cache"
/usr/bin/xcrun swiftc -O -module-cache-path "$PWD/build/swift-cache" Runner.swift -o "$APP/Contents/MacOS/NightlyTimeMachine"
/usr/bin/install -m 755 backup.sh "$APP/Contents/Resources/backup.sh"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.nightly-time-machine.runner</string>
<key>CFBundleName</key><string>Nightly Time Machine</string>
<key>CFBundleExecutable</key><string>NightlyTimeMachine</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign - --identifier local.nightly-time-machine.runner "$APP"
/usr/bin/codesign --verify --strict "$APP"
