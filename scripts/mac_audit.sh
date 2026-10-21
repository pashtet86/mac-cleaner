#!/bin/bash
# mac_audit.sh — read-only security triage for macOS. Changes nothing on the system.
# Usage:  bash mac_audit.sh          (basic)
#         sudo bash mac_audit.sh     (more complete: all users' processes/sockets, login items, profiles)
# Report is written to ~/mac_audit_<timestamp>.txt

OUT="$HOME/mac_audit_$(date +%Y%m%d_%H%M%S).txt"
exec > >(tee "$OUT") 2>&1
sec() { printf '\n===== %s =====\n' "$1"; }
signer() {  # print first signing authority / team, or UNSIGNED
  local info
  info=$(codesign -dv --verbose=2 "$1" 2>&1)
  if   echo "$info" | grep -q "not signed";        then echo "UNSIGNED"
  elif echo "$info" | grep -q "Signature=adhoc";   then echo "ADHOC-SIGNED"
  else echo "$info" | grep -m1 "^Authority=" | sed 's/^Authority=//'; fi
}

sec "System"
sw_vers; uname -m; [ "$EUID" -eq 0 ] && echo "(running as root)"

sec "Built-in protections"
echo -n "SIP: ";        csrutil status
echo -n "Gatekeeper: "; spctl --status
echo -n "FileVault: ";  fdesetup status
echo -n "Firewall: ";   /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
echo "XProtect / MRT updates (latest):"
system_profiler SPInstallHistoryDataType 2>/dev/null | grep -A3 -E "XProtect|MRT" | tail -n 8

sec "Persistence: LaunchAgents / LaunchDaemons (with signer of target binary)"
for d in "$HOME/Library/LaunchAgents" /Library/LaunchAgents /Library/LaunchDaemons; do
  for p in "$d"/*.plist; do
    [ -e "$p" ] || continue
    prog=$(/usr/libexec/PlistBuddy -c "Print :Program" "$p" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "$p" 2>/dev/null)
    if [ -n "$prog" ] && [ -e "$prog" ]; then s=$(signer "$prog"); else s="TARGET MISSING"; fi
    echo "$p"
    echo "    -> $prog  [$s]"
  done
done

sec "Loaded non-Apple launchd jobs"
launchctl list | grep -v -E "com\.apple\.|^-\s+0\s+com\.apple" | head -200

sec "Login items / background items"
if [ "$EUID" -eq 0 ]; then
  sfltool dumpbtm 2>/dev/null | grep -E "Name:|Developer Name:|Executable Path:|URL:|Disposition:" | grep -v "com.apple"
else
  osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null
  echo "(run with sudo for the full Background Task Management list)"
fi

sec "Cron / periodic / emond"
crontab -l 2>/dev/null || echo "no user crontab"
[ "$EUID" -eq 0 ] && ls -la /usr/lib/cron/tabs 2>/dev/null
ls -la /etc/periodic/daily /etc/periodic/weekly /etc/periodic/monthly 2>/dev/null | grep -v -E "^total|^d"
ls -la /etc/emond.d/rules 2>/dev/null

sec "Kernel & system extensions"
systemextensionsctl list 2>/dev/null
kextstat 2>/dev/null | grep -v com.apple

sec "Configuration profiles (MDM can install proxies/root certs)"
profiles list 2>/dev/null
[ "$EUID" -eq 0 ] && profiles show -type configuration 2>/dev/null | grep -E "name:|organization:|identifier:"

sec "Authorization plugins / Directory Services plugins"
ls -la /Library/Security/SecurityAgentPlugins 2>/dev/null
ls -la /Library/DirectoryServices/PlugIns 2>/dev/null

sec "Running processes: unsigned or ad-hoc signed executables"
ps -axo pid=,comm= | while read -r pid path; do
  [ -f "$path" ] || continue
  s=$(signer "$path")
  case "$s" in UNSIGNED|ADHOC-SIGNED) echo "$s  pid=$pid  $path";; esac
done | sort -u -k3

sec "Processes running from temp / shared / hidden locations"
ps -axo pid=,user=,args= | grep -E "(/tmp/|/private/tmp/|/Users/Shared/|/private/var/folders/|/\.[A-Za-z0-9_-]+/)" | grep -v -E "grep|mac_audit"

sec "Listening sockets"
lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null
lsof -nP -iUDP 2>/dev/null | grep -v -E "mDNSRespo|launchd|localhost" | head -60

sec "Established outbound connections"
lsof -nP -iTCP -sTCP:ESTABLISHED 2>/dev/null | awk '{print $1, $3, $9}' | sort -u

sec "DNS & proxy settings"
scutil --dns | grep nameserver | sort -u
scutil --proxy | grep -E "Enable|Proxy|Port|PAC" | grep -v ": 0"
echo "--- /etc/hosts (non-default lines):"
grep -v -E "^\s*#|^\s*$|localhost|broadcasthost" /etc/hosts

sec "Non-Apple root certificates in System keychain"
security find-certificate -a -p /Library/Keychains/System.keychain 2>/dev/null \
  | awk '/BEGIN/{c=""} {c=c $0 "\n"} /END/{print c | "openssl x509 -noout -subject"; close("openssl x509 -noout -subject")}' 2>/dev/null

sec "sudoers.d"
ls -la /etc/sudoers.d 2>/dev/null

sec "Suspicious lines in shell startup files"
for f in ~/.zshrc ~/.zprofile ~/.zshenv ~/.zlogin ~/.bashrc ~/.bash_profile ~/.profile /etc/zshrc /etc/profile; do
  [ -f "$f" ] && grep -n -H -E "curl|wget|base64|osascript|eval|nc |/tmp/|python -c|DYLD_" "$f"
done

sec "Applications: signer of each app in /Applications and ~/Applications"
for a in /Applications/*.app ~/Applications/*.app; do
  [ -d "$a" ] || continue
  s=$(signer "$a")
  echo "$s | $a"
done | sort | grep -v -E "Software Signing$|Apple Mac OS Application Signing"

sec "Browser extensions"
for base in "$HOME/Library/Application Support/Google/Chrome" \
            "$HOME/Library/Application Support/BraveSoftware/Brave-Browser" \
            "$HOME/Library/Application Support/Microsoft Edge" \
            "$HOME/Library/Application Support/Arc/User Data"; do
  [ -d "$base" ] || continue
  echo "--- $base"
  find "$base" -path "*/Extensions/*/manifest.json" -maxdepth 5 2>/dev/null | while read -r m; do
    id=$(echo "$m" | awk -F/ '{print $(NF-2)}')
    name=$(grep -m1 '"name"' "$m" | sed 's/.*"name": *"\([^"]*\)".*/\1/')
    echo "$id  $name"
  done | sort -u
done
ls "$HOME/Library/Application Support/Firefox/Profiles/"*/extensions 2>/dev/null
pluginkit -mAvvv -p com.apple.Safari.web-extension 2>/dev/null | grep -E "^\s+\S+\(" | head -50

sec "Executables in ~/Library modified in last 14 days"
find "$HOME/Library" -type f -perm +111 -mtime -14 2>/dev/null \
  | grep -v -E "/Caches/|/Containers/|/Group Containers/|\.dylib$|/Logs/" | head -100

sec "Executables in /tmp, /Users/Shared"
find /tmp /private/tmp /Users/Shared -type f -perm +111 2>/dev/null | head -50

echo
echo "Done. Report saved to: $OUT"
