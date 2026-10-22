#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
if ! xcrun --find swift >/dev/null 2>&1; then
    echo 'Apple Command Line Tools are missing or incomplete.' >&2
    echo 'Install the Command Line Tools package from developer.apple.com/download/all/.' >&2
    exit 1
fi
# Only build and package. Never launch or change Bluetooth settings here.
swift build -c release --arch arm64
bin_dir="$(swift build -c release --arch arm64 --show-bin-path)"
app_dir="$PWD/build/Joycontrol.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/joycontrol-macos" "$app_dir/Contents/MacOS/joycontrol-macos"
cp joycontrol-macos/NintendoSwitchControllerSDP.plist "$app_dir/Contents/Resources/"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>joycontrol-macos</string>
<key>CFBundleIdentifier</key><string>local.joycontrol.macos</string>
<key>CFBundleName</key><string>Joycontrol</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>11.0</string>
<key>NSBluetoothAlwaysUsageDescription</key><string>Emulates a Nintendo Switch controller over Bluetooth.</string>
</dict></plist>
PLIST
codesign --force --sign - --entitlements joycontrol-macos/joycontrol_macos.entitlements "$app_dir"
printf 'Built app: %s\n' "$app_dir"
echo 'Not launched. Running the app changes Bluetooth discovery and pairing settings.'
