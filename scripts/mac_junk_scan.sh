#!/bin/bash
# mac_junk_scan.sh — read-only: measures disk space taken by caches/leftovers. Deletes nothing.
# Usage: bash mac_junk_scan.sh   → report in ~/mac_junk_<timestamp>.txt

OUT="$HOME/mac_junk_$(date +%Y%m%d_%H%M%S).txt"
exec > >(tee "$OUT") 2>&1
H="$HOME"
sec() { printf '\n===== %s =====\n' "$1"; }
sz()  { # label, path...
  local label="$1"; shift
  local total
  total=$(du -sck "$@" 2>/dev/null | tail -1 | awk '{print $1}')
  [ -n "$total" ] && [ "$total" -gt 10240 ] && printf '%8s MB  %s\n' "$((total/1024))" "$label"
}

sec "Disk"
df -h / | tail -1

sec "SAFE — regenerated automatically"
sz "User caches (~/Library/Caches)"                     "$H/Library/Caches"
sz "User logs"                                          "$H/Library/Logs"
sz "Trash"                                              "$H/.Trash"
sz "Xcode DerivedData"                                  "$H/Library/Developer/Xcode/DerivedData"
sz "Xcode module cache"                                 "$H/Library/Developer/Xcode/ModuleCache.noindex" "$H/Library/Caches/com.apple.dt.Xcode"
sz "CocoaPods cache"                                    "$H/Library/Caches/CocoaPods"
sz "Homebrew downloads cache"                           "$(brew --cache 2>/dev/null)"
sz "npm cache"                                          "$H/.npm/_cacache"
sz "yarn cache"                                         "$H/Library/Caches/Yarn"
sz "pnpm store"                                         "$H/Library/pnpm/store" "$H/.pnpm-store"
sz "Expo / Metro caches"                                "$H/.expo" "$TMPDIR/metro-cache" "$TMPDIR/haste-map"*
sz "Gradle caches"                                      "$H/.gradle/caches"
sz "pip cache"                                          "$H/Library/Caches/pip"
sz "Steam download/shader cache"                        "$H/Library/Application Support/Steam/appcache" "$H/Library/Application Support/Steam/steamapps/shadercache" "$H/Library/Application Support/Steam/steamapps/downloading"
sz "Battle.net / StarCraft II cache"                    "/Users/Shared/Blizzard/Battle.net/Cache" "/Users/Shared/Blizzard/StarCraft II/Maps/Cache"
sz "Adobe media cache"                                  "$H/Library/Application Support/Adobe/Common/Media Cache Files" "$H/Library/Application Support/Adobe/Common/Media Cache"
sz "Slack cache"                                        "$H/Library/Application Support/Slack/Cache" "$H/Library/Application Support/Slack/Service Worker/CacheStorage"
sz "Spotify cache"                                      "$H/Library/Caches/com.spotify.client"
sz "Figma cache"                                        "$H/Library/Application Support/Figma/DesktopProfile"

sec "PROBABLY SAFE — old versions left by updaters"
for d in "$H/Library/Application Support/Claude/claude-code" \
         "$H/Library/Application Support/ViberPC" \
         "$H/Library/Application Support/Google/GoogleUpdater" \
         "$H/Library/Application Support/Dropbox/DropboxUpdater" \
         "$H/Library/Application Support/dev.warp.Warp-Stable/autoupdate"; do
  [ -d "$d" ] || continue
  echo "--- $d"
  du -sh "$d"/*/ 2>/dev/null | sort -k2
done
sz "Old Xcode iOS DeviceSupport (re-downloaded on device connect)" "$H/Library/Developer/Xcode/iOS DeviceSupport"
echo "--- iOS DeviceSupport versions:"
ls "$H/Library/Developer/Xcode/iOS DeviceSupport" 2>/dev/null

sec "REVIEW — may contain things you want"
sz "Xcode Archives (needed to symbolicate old App Store builds)" "$H/Library/Developer/Xcode/Archives"
sz "iOS Simulators data"                                "$H/Library/Developer/CoreSimulator/Devices"
echo "--- Unavailable simulators (safe: xcrun simctl delete unavailable):"
xcrun simctl list devices unavailable 2>/dev/null | grep -c "unavailable" | xargs echo "count:"
sz "Simulator runtimes"                                 "/Library/Developer/CoreSimulator/Volumes" "/Library/Developer/CoreSimulator/Profiles/Runtimes"
sz "iPhone/iPad backups"                                "$H/Library/Application Support/MobileSync/Backup"
sz "Docker disk image"                                  "$H/Library/Containers/com.docker.docker/Data/vms"
docker system df 2>/dev/null
sz "Telegram media"                                     "$H/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram"
sz "WhatsApp media"                                     "$H/Library/Group Containers/group.net.whatsapp.WhatsApp.shared"
sz "Mail downloads"                                     "$H/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"
sz "Downloads folder"                                   "$H/Downloads"
sz "DiffusionBee models"                                "$H/.diffusionbee"
sz "Hugging Face / Ollama models"                       "$H/.cache/huggingface" "$H/.ollama/models"

sec "REVIEW — node_modules folders in ~ (top 20)"
find "$H" -maxdepth 5 -type d -name node_modules -prune \
     -not -path "*/Library/*" -not -path "*/.Trash/*" 2>/dev/null \
  | while read -r d; do du -sk "$d" 2>/dev/null; done | sort -rn | head -20 \
  | awk '{s=$1; $1=""; printf "%8d MB %s\n", s/1024, $0}'

sec "REVIEW — leftovers of uninstalled apps in Application Support (top 40 by size)"
du -sk "$H/Library/Application Support"/*/ 2>/dev/null | sort -rn | head -40 \
  | awk '{s=$1; $1=""; printf "%8d MB %s\n", s/1024, $0}'

sec "REVIEW — largest files in home (>500 MB)"
find "$H" -type f -size +500M -not -path "*/Library/Containers/com.docker.docker/*" \
     -not -path "*/Library/Mobile Documents/*" 2>/dev/null \
  | while read -r f; do du -sk "$f"; done | sort -rn | head -30 \
  | awk '{s=$1; $1=""; printf "%8d MB %s\n", s/1024, $0}'

echo
echo "Done. Report saved to: $OUT"
