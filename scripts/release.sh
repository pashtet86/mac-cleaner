#!/usr/bin/env bash
# Publishes a new version to everyone who has Disk Cleaner installed.
#
#   scripts/release.sh 1.1
#
# 1. Sets the version (MARKETING_VERSION = 1.1, build number + 1) in the Xcode project.
# 2. Builds, signs with Developer ID and notarizes the DMG (scripts/make_dmg.sh).
# 3. Writes release notes from the "## [1.1]" section of CHANGELOG.md.
# 4. Signs the DMG with the EdDSA update key and adds it to appcast.xml (Sparkle's generate_appcast).
# 5. After you confirm, uploads the DMG, a "latest" copy and the appcast to the R2 bucket behind
#    downloads.machealthapps.com. Installed apps find it on their next daily check.
#
# Needs: the notarytool profile (README), the EdDSA private key in this Mac's Keychain
# (created once with Sparkle's generate_keys --account com.machealthapps.diskcleaner) and
# `npx wrangler login`. The key never leaves the Keychain; back it up with generate_keys -x.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || { echo "Usage: scripts/release.sh <version, e.g. 1.1>" >&2; exit 1; }

FEED_HOST="https://downloads.machealthapps.com"
BUCKET="mac-health-app"
KEY_ACCOUNT="com.machealthapps.diskcleaner"
PROJECT=MacDiskCleaner.xcodeproj/project.pbxproj
UPDATES=build/updates
DMG_NAME="DiskCleaner-$VERSION.dmg"

grep -q "^## \[$VERSION\]" CHANGELOG.md || {
    echo "✖ CHANGELOG.md has no \"## [$VERSION]\" section — write the release notes first." >&2
    exit 1
}

echo "› Setting version $VERSION"
BUILD=$(( $(grep -m1 -o 'CURRENT_PROJECT_VERSION = [0-9]*' "$PROJECT" | grep -o '[0-9]*$') + 1 ))
sed -i '' -E "s/MARKETING_VERSION = [0-9.]+;/MARKETING_VERSION = $VERSION;/; s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $BUILD;/" "$PROJECT"
echo "  $VERSION (build $BUILD)"

echo "› Resolving Sparkle tools"
xcodebuild -resolvePackageDependencies -project MacDiskCleaner.xcodeproj -scheme MacDiskCleaner \
    -derivedDataPath build/DerivedData-release -quiet
SPARKLE_BIN=build/DerivedData-release/SourcePackages/artifacts/sparkle/Sparkle/bin

SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}" \
NOTARY_PROFILE="${NOTARY_PROFILE:-macdiskcleaner-notary}" \
TELEMETRY_ENDPOINT="${TELEMETRY_ENDPOINT:-}" \
    scripts/make_dmg.sh

echo "› Preparing the appcast"
mkdir -p "$UPDATES"
# Start from the published appcast so earlier versions stay listed.
curl -fsS "$FEED_HOST/appcast.xml" -o "$UPDATES/appcast.xml" 2>/dev/null || rm -f "$UPDATES/appcast.xml"
cp "build/dist/$DMG_NAME" "$UPDATES/"

# Release notes: the CHANGELOG section as HTML, embedded in the appcast and shown in the update window.
awk -v v="$VERSION" '
    $0 ~ "^## \\[" v "\\]" { on = 1; next }
    on && /^## \[/ { exit }
    on { print }
' CHANGELOG.md | python3 -c '
import html, re, sys
out, in_list = [], False
for line in sys.stdin.read().splitlines():
    if line.startswith("### "):
        if in_list: out.append("</ul>"); in_list = False
        out.append("<h3>%s</h3>" % html.escape(line[4:]))
    elif line.startswith("- "):
        if not in_list: out.append("<ul>"); in_list = True
        out.append("<li>%s" % html.escape(line[2:]))
    elif line.startswith("  ") and in_list:
        out.append(html.escape(line.strip()))
if in_list: out.append("</ul>")
print("<meta charset=\"utf-8\"><style>body{font:13px -apple-system;margin:0 4px}h3{font-size:13px;margin:12px 0 4px}</style>")
print("\n".join(out))
' > "$UPDATES/DiskCleaner-$VERSION.html"

"$SPARKLE_BIN/generate_appcast" --account "$KEY_ACCOUNT" \
    --download-url-prefix "$FEED_HOST/" --link "https://machealthapps.com" \
    --maximum-deltas 0 --embed-release-notes "$UPDATES"
echo "  $(grep -c '<item>' "$UPDATES/appcast.xml") version(s) in the appcast"

echo
read -r -p "Publish Disk Cleaner $VERSION to $FEED_HOST now? Users will be offered it. [y/N] " answer
[[ "$answer" =~ ^[Yy]$ ]] || { echo "Not published. Everything is in $UPDATES."; exit 0; }

put() { npx --yes wrangler r2 object put "$BUCKET/$1" --file "$2" --remote "${@:3}"; }
put "$DMG_NAME" "$UPDATES/$DMG_NAME" --content-type application/x-apple-diskimage
put "DiskCleaner.dmg" "$UPDATES/$DMG_NAME" --content-type application/x-apple-diskimage --cache-control "max-age=300"
# Last, so no app is offered a file that isn't uploaded yet.
put "appcast.xml" "$UPDATES/appcast.xml" --content-type application/xml --cache-control "max-age=300"

echo
echo "✔ Published $VERSION. Next:"
echo "  git commit -am \"chore(release): $VERSION\" && git tag v$VERSION && git push --follow-tags"
echo "  Update the download block in website/index.html (size and SHA-256 printed above)."
