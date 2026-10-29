#!/bin/sh
# Builds the spike DesknetAgent.framework for iphoneos and macosx into
# ~/Library/Application Support/Desknet/Agent/<platform>/, where the build phase looks for it.
# ponytail: spike only; Desknet.app ships and installs these itself in Phase 2.
set -eu
cd "$(dirname "$0")"
OUT="$HOME/Library/Application Support/Desknet/Agent"

plist() { # $1 = path, $2 = platform, $3 = min-version key
    cat > "$1" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>DesknetAgent</string>
  <key>CFBundleIdentifier</key><string>dev.desknet.agent</string>
  <key>CFBundleName</key><string>DesknetAgent</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleSupportedPlatforms</key><array><string>$2</string></array>
  <key>$3</key><string>15.0</string>
</dict></plist>
EOF
}

# iOS device: flat framework bundle.
F="$OUT/iphoneos/DesknetAgent.framework"
rm -rf "$F" && mkdir -p "$F"
xcrun -sdk iphoneos clang -target arm64-apple-ios15.0 -fobjc-arc -dynamiclib -framework Foundation \
    -install_name @rpath/DesknetAgent.framework/DesknetAgent agent_framework.m -o "$F/DesknetAgent"
plist "$F/Info.plist" iPhoneOS MinimumOSVersion
codesign -s - -f "$F" >/dev/null 2>&1

# macOS: versioned framework bundle.
F="$OUT/macosx/DesknetAgent.framework"
rm -rf "$F" && mkdir -p "$F/Versions/A/Resources"
xcrun -sdk macosx clang -target arm64-apple-macos14.0 -fobjc-arc -dynamiclib -framework Foundation \
    -install_name @rpath/DesknetAgent.framework/Versions/A/DesknetAgent agent_framework.m -o "$F/Versions/A/DesknetAgent"
plist "$F/Versions/A/Resources/Info.plist" MacOSX LSMinimumSystemVersion
ln -s A "$F/Versions/Current"
ln -s Versions/Current/DesknetAgent "$F/DesknetAgent"
ln -s Versions/Current/Resources "$F/Resources"
codesign -s - -f "$F" >/dev/null 2>&1

echo "built: $OUT/{iphoneos,macosx}/DesknetAgent.framework"
