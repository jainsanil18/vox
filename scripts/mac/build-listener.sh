# build-listener.sh - compile VoxListener.app into the state dir if it's
# missing or its source changed. Prints the app path on success.
# Rebuild only when needed: macOS ties the mic/speech permission grants to
# the exact binary, so every rebuild means clicking Allow again.

. "$(dirname "$0")/common.sh"

src="$VOX_DIR/listener/VoxListener.swift"
app="$VOX_STATE/VoxListener.app"
stamp="$app/Contents/Resources/source.sha"
want=$(shasum "$src" | cut -d' ' -f1)

if [ -x "$app/Contents/MacOS/VoxListener" ] && [ "$(cat "$stamp" 2>/dev/null)" = "$want" ]; then
    echo "$app"
    exit 0
fi

if ! xcrun --find swiftc > /dev/null 2>&1; then
    echo "Vox needs the Xcode Command Line Tools to build its listener. Run: xcode-select --install" >&2
    exit 1
fi

tmp=$(mktemp -d)
mkdir -p "$tmp/VoxListener.app/Contents/MacOS" "$tmp/VoxListener.app/Contents/Resources"
cat > "$tmp/VoxListener.app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.github.vox.listener</string>
    <key>CFBundleName</key><string>Vox Listener</string>
    <key>CFBundleExecutable</key><string>VoxListener</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>Vox listens for your wake word and dictates commands to Claude Code.</string>
    <key>NSSpeechRecognitionUsageDescription</key><string>Vox turns your speech into Claude Code prompts, on this Mac.</string>
    <key>NSAppleEventsUsageDescription</key><string>Vox types your voice commands into the terminal running Claude Code.</string>
</dict>
</plist>
EOF

if ! xcrun swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos15.0" \
        -o "$tmp/VoxListener.app/Contents/MacOS/VoxListener" "$src" 2> "$tmp/build.log"; then
    vox_log "listener build failed: $(tr '\n' ' ' < "$tmp/build.log" | cut -c1-500)" build
    echo "VoxListener failed to build. Details: $tmp/build.log" >&2
    exit 1
fi
codesign --force --sign - "$tmp/VoxListener.app" 2>/dev/null
printf '%s\n' "$want" > "$tmp/VoxListener.app/Contents/Resources/source.sha"

rm -rf "$app"
mv "$tmp/VoxListener.app" "$app"
rm -rf "$tmp"
vox_log "built $app" build
echo "$app"
