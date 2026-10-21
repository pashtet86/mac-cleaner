#!/bin/bash
# mac_dupes_big.sh — read-only: finds large files/folders, installers and duplicate files. Deletes nothing.
# Usage:  bash mac_dupes_big.sh
#         MIN_BIG_MB=200 MIN_DUP_MB=5 bash mac_dupes_big.sh   (custom thresholds)
# Report: ~/mac_dupes_big_<timestamp>.txt
#
# Cloud folders (~/Library/CloudStorage — Dropbox/Google Drive, ~/Library/Mobile Documents — iCloud)
# are skipped on purpose: reading online-only files there would download them.

OUT="$HOME/mac_dupes_big_$(date +%Y%m%d_%H%M%S).txt"
exec > >(tee "$OUT") 2>&1
H="$HOME"
MIN_BIG_MB=${MIN_BIG_MB:-500}
MIN_DUP_MB=${MIN_DUP_MB:-1}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
sec() { printf '\n===== %s =====  [%s]\n' "$1" "$(date +%H:%M:%S)"; }
NOCLOUD=(-I CloudStorage -I "Mobile Documents")  # du: don't walk cloud folders (online-only files hang/download)
mb()  { awk '{s=$1; $1=""; printf "%9.1f GB %s\n", s/1048576, $0}'; }

sec "Biggest folders in home"
du -k -d 1 "${NOCLOUD[@]}" "$H" 2>/dev/null | sort -rn | head -20 | mb

sec "Biggest folders in ~/Library"
du -k -d 1 "${NOCLOUD[@]}" "$H/Library" "$H/Library/Application Support" "$H/Library/Containers" \
     "$H/Library/Group Containers" 2>/dev/null | sort -rn | head -30 | mb

sec "Files larger than ${MIN_BIG_MB} MB (top 50)"
find "$H" \( -path "$H/Library/CloudStorage" -o -path "$H/Library/Mobile Documents" \) -prune \
     -o -type f -size +"${MIN_BIG_MB}"M -print0 2>/dev/null \
  | xargs -0 stat -f '%z %m %N' 2>/dev/null | sort -rn | head -50 \
  | awk '{s=$1; m=$2; $1=$2=""; cmd="date -r " m " +%Y-%m-%d"; cmd | getline d; close(cmd);
          printf "%8.1f GB  %s %s\n", s/1073741824, d, $0}'

sec "Installers & archives in Downloads / Desktop / Documents (>20 MB)"
find "$H/Downloads" "$H/Desktop" "$H/Documents" -type f -size +20M \
     \( -iname "*.dmg" -o -iname "*.pkg" -o -iname "*.zip" -o -iname "*.iso" -o -iname "*.xip" \
        -o -iname "*.rar" -o -iname "*.7z" -o -iname "*.tar*" -o -iname "*.ipa" -o -iname "*.apk" \) \
     -print0 2>/dev/null | xargs -0 stat -f '%z %N' 2>/dev/null | sort -rn | head -50 \
  | awk '{s=$1; $1=""; printf "%8.1f MB %s\n", s/1048576, $0}'

sec "Duplicate files (>= ${MIN_DUP_MB} MB, outside ~/Library, apps, caches, node_modules, .git)"
echo "(indexing — may take a few minutes)"
find "$H" \( -path "$H/Library" -o -path "$H/Applications" -o -path "$H/.Trash" \
             -o -name node_modules -o -name .git -o -name Pods -o -name DerivedData \
             -o -name "*.photoslibrary" -o -name "*.app" \
             -o \( -type d -name ".*" \) \) -prune \
     -o -type f -size +"${MIN_DUP_MB}"M -print0 2>/dev/null \
  | xargs -0 stat -f '%z %N' 2>/dev/null > "$TMP/sizes"

# Only files that share an exact size with another file can be duplicates
awk '{c[$1]++} END{for (s in c) if (c[s]>1) print s}' "$TMP/sizes" > "$TMP/dupsizes"
awk 'NR==FNR{d[$1]=1; next} ($1 in d)' "$TMP/dupsizes" "$TMP/sizes" > "$TMP/candidates"
echo "files scanned: $(wc -l < "$TMP/sizes" | tr -d ' '), same-size candidates: $(wc -l < "$TMP/candidates" | tr -d ' ')"

while IFS= read -r line; do
  size=${line%% *}; f=${line#* }
  h=$(md5 -q "$f" 2>/dev/null) || continue
  printf '%s\t%s\t%s\n' "$h" "$size" "$f"
done < "$TMP/candidates" | sort > "$TMP/hashes"

awk -F'\t' '
  function out() { if (n > 1) { w = (n-1)*sz; total += w; groups++
      printf "%d\t%d copies x %.1f MB — wasted %.1f MB%s\n", w, n, sz/1048576, w/1048576, files } }
  $1 != prev { out(); prev = $1; n = 0; files = "" }
  { n++; sz = $2; files = files "\001    " $3 }
  END { out(); printf "999999999999999\tTOTAL: %d duplicate groups, %.2f GB reclaimable\n", groups, total/1073741824 }
' "$TMP/hashes" | sort -t$'\t' -k1,1rn | head -61 | cut -f2- | tr '\001' '\n'

echo
echo "Done. Report saved to: $OUT"
