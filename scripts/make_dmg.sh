#!/usr/bin/env bash
# Builds a universal Release DevSpace.app and packages it as a drag-to-Applications DMG.
#
#   scripts/make_dmg.sh                       # ad-hoc signed: testers allow it once in System Settings
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
#   NOTARY_PROFILE=devspace-notary \
#   scripts/make_dmg.sh                       # signed + notarized: opens without warnings
#
# NOTARY_PROFILE is a notarytool keychain profile, created once with
#   xcrun notarytool store-credentials devspace-notary --apple-id <id> --team-id <TEAMID>
# (it prompts for an app-specific password and keeps it in the keychain — never in this repo).
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED=build/DerivedData-release
OUT=build/dist
STAGING="$OUT/staging"

echo "› Building universal Release app"
xcodebuild -project DevSpace.xcodeproj -scheme DevSpace -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO -quiet build

APP="$DERIVED/Build/Products/Release/DevSpace.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="$OUT/DevSpace-$VERSION.dmg"

if [ -n "${SIGN_IDENTITY:-}" ]; then
    echo "› Signing with Developer ID"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"

echo "› Creating $DMG"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/DevSpace.app"
ln -s /Applications "$STAGING/Applications"
# hdiutil prints a deprecation notice on every run; keep everything else.
hdiutil create -volname "DevSpace" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" 2>&1 | grep -v deprecated || true
rm -rf "$STAGING"
[ -f "$DMG" ] || { echo "✖ hdiutil did not create $DMG" >&2; exit 1; }

if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
    if [ -n "${NOTARY_PROFILE:-}" ]; then
        echo "› Notarizing (takes a few minutes)"
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
    fi
fi

echo
echo "✔ $DMG ($(du -h "$DMG" | cut -f1))"
echo "  SHA-256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo "  Architectures: $(lipo -archs "$APP/Contents/MacOS/DevSpace")"
if [ -z "${SIGN_IDENTITY:-}" ]; then
    echo "  Ad-hoc signed — testers must allow it once (README → Sharing a test build)."
fi
