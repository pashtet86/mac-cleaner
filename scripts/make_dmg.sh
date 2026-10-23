#!/usr/bin/env bash
# Builds a universal Release "Disk Cleaner.app" and packages it as a drag-to-Applications DMG.
#
#   scripts/make_dmg.sh                       # ad-hoc signed: testers allow it once in System Settings
#   TELEMETRY_ENDPOINT=https://… scripts/make_dmg.sh   # adds opt-in anonymous statistics (see telemetry/)
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
#   NOTARY_PROFILE=macdiskcleaner-notary \
#   scripts/make_dmg.sh                       # signed + notarized: opens without warnings
#
# NOTARY_PROFILE is a notarytool keychain profile, created once with
#   xcrun notarytool store-credentials macdiskcleaner-notary --apple-id <id> --team-id <TEAMID>
# (it prompts for an app-specific password and keeps it in the keychain — never in this repo).
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED=build/DerivedData-release
OUT=build/dist
STAGING="$OUT/staging"

# Ad-hoc builds have no Team ID, so the hardened runtime would refuse to load the embedded Sparkle
# framework. Notarized builds need it and get it.
HARDENED=$([ -n "${SIGN_IDENTITY:-}" ] && echo YES || echo NO)

# Never overwrite a notarized DMG: it may be the published one. Bump the version instead.
EXISTING="$OUT/DiskCleaner-$(grep -m1 -o 'MARKETING_VERSION = [0-9.]*' MacDiskCleaner.xcodeproj/project.pbxproj | grep -o '[0-9.]*$').dmg"
if [ -f "$EXISTING" ] && xcrun stapler validate "$EXISTING" >/dev/null 2>&1; then
    echo "✖ $EXISTING is notarized — bump the version (scripts/release.sh) or move it away first." >&2
    exit 1
fi

# macOS protects an app bundle that has been launched (App Management), so a rebuild can't write
# into it. Move old products aside; remove whatever of them can be removed.
if [ -d "$DERIVED/Build/Products" ]; then
    mv "$DERIVED/Build/Products" "$DERIVED/Build/Products.stale.$$"
    rm -rf "$DERIVED/Build/"Products.stale.* 2>/dev/null || true
fi

echo "› Building universal Release app"
xcodebuild -project MacDiskCleaner.xcodeproj -scheme MacDiskCleaner -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO TELEMETRY_ENDPOINT="${TELEMETRY_ENDPOINT:-}" \
    CODE_SIGN_IDENTITY="${SIGN_IDENTITY:--}" OTHER_CODE_SIGN_FLAGS="${SIGN_IDENTITY:+--timestamp}" \
    ENABLE_HARDENED_RUNTIME="$HARDENED" -quiet build

APP="$DERIVED/Build/Products/Release/Disk Cleaner.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="$OUT/DiskCleaner-$VERSION.dmg"

if [ -n "${SIGN_IDENTITY:-}" ]; then
    echo "› Signing with Developer ID"
    # Sparkle's helpers ship ad-hoc signed; notarization needs every one signed, inside out.
    SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
    sign() { codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$@"; }
    sign "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
    sign --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
    sign "$SPARKLE/Versions/B/Autoupdate"
    sign "$SPARKLE/Versions/B/Updater.app"
    sign "$SPARKLE"
    sign "$APP"
fi
codesign --verify --strict --deep "$APP"

echo "› Creating $DMG"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/Disk Cleaner.app"
ln -s /Applications "$STAGING/Applications"
# hdiutil prints a deprecation notice on every run; keep everything else.
hdiutil create -volname "Disk Cleaner" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" 2>&1 | grep -v deprecated || true
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
echo "  Architectures: $(lipo -archs "$APP/Contents/MacOS/Disk Cleaner")"
if [ -z "${SIGN_IDENTITY:-}" ]; then
    echo "  Ad-hoc signed — testers must allow it once (README → Sharing a test build)."
fi
