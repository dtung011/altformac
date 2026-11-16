#!/bin/sh
# Builds AltForMac.app and AltForMac-<version>.dmg in ./dist
#
#   scripts/package.sh                         ad-hoc signed (works on this Mac; others must right-click > Open)
#   VERSION=0.1.1 scripts/package.sh           overrides the number in the VERSION file
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/package.sh
#   SIGN_IDENTITY=... NOTARY_PROFILE=altformac scripts/package.sh     also notarizes and staples
#
# NOTARY_PROFILE is a keychain profile made once with:
#   xcrun notarytool store-credentials altformac --apple-id YOU --team-id TEAMID --password APP_SPECIFIC_PASSWORD
set -e
cd "$(dirname "$0")/.."
VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="dist/AltForMac.app"
DMG="dist/AltForMac-$VERSION.dmg"

echo "==> build (release)"
if swift build -c release --arch arm64 --arch x86_64 >/dev/null 2>&1; then
  BIN=".build/apple/Products/Release/AltForMac"; echo "    universal (arm64 + x86_64)"
else
  swift build -c release; BIN="$(swift build -c release --show-bin-path)/AltForMac"; echo "    native arch only"
fi

echo "==> assemble $APP"
rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AltForMac"
cp Sources/AltForMac/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
cp mappings/*.yaml "$APP/Contents/Resources/"
cp packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE" 2>/dev/null || true

echo "==> sign ($SIGN_IDENTITY)"
if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --deep --sign - "$APP"
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --deep --strict "$APP"
"$APP/Contents/MacOS/AltForMac" --self-test

echo "==> dmg"
# A read-write image gets the drag-to-Applications window (background, icon positions) set by
# Finder, then is compressed. Finder asks once for Automation permission for your terminal.
# Artwork comes from packaging/ (regenerate with: swift scripts/make-art.swift).
VOL="AltForMac"
if [ -d "/Volumes/$VOL" ]; then
  echo "    ejecting the mounted /Volumes/$VOL first"
  hdiutil detach "/Volumes/$VOL" -force >/dev/null
fi
STAGE="$(mktemp -d)"
RW="$(mktemp -d)/rw.dmg"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/.background"
cp packaging/dmg-background.tiff "$STAGE/.background/background.tiff"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ "$RW" >/dev/null
rm -rf "$STAGE"
DEV="$(hdiutil attach -readwrite -noverify -noautoopen -mountpoint "/Volumes/$VOL" "$RW" | awk '/Apple_HFS/ {print $1}')"
osascript <<EOF
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 520}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "AltForMac.app" of container window to {170, 200}
    set position of item "Applications" of container window to {490, 200}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
# Set after the Finder step: Finder rewrites the volume root and drops the icon if it is added earlier.
cp packaging/AppIcon.icns "/Volumes/$VOL/.VolumeIcon.icns"
SetFile -a C "/Volumes/$VOL"
sync
hdiutil detach "$DEV" >/dev/null
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG" >/dev/null
rm -f "$RW"
[ "$SIGN_IDENTITY" != "-" ] && codesign --force --sign "$SIGN_IDENTITY" "$DMG"

if [ -n "$NOTARY_PROFILE" ] && [ "$SIGN_IDENTITY" != "-" ]; then
  echo "==> notarize (takes a few minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

# Same bytes under a fixed name, so releases/latest/download/AltForMac.dmg always serves the newest DMG.
cp "$DMG" dist/AltForMac.dmg

echo "==> done"
shasum -a 256 "$DMG"
ls -lh "$DMG"
