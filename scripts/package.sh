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
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "AltForMac" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
[ "$SIGN_IDENTITY" != "-" ] && codesign --force --sign "$SIGN_IDENTITY" "$DMG"

if [ -n "$NOTARY_PROFILE" ] && [ "$SIGN_IDENTITY" != "-" ]; then
  echo "==> notarize (takes a few minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo "==> done"
shasum -a 256 "$DMG"
ls -lh "$DMG"
