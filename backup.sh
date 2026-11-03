#!/bin/bash
set -uo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
UUID=89AD4B37-ACCB-4C87-8534-F0EF2885C3E3
PERSONAL=C6E2B959-97F0-47B2-BFA3-1562924BC1FB
DEST=F5B110C7-E523-44B8-9FDD-F49AA55AE434
STATE=/var/db/local.nightly-time-machine
mkdir -p "$STATE"
log() { printf '%s %s\n' "$(date '+%F %T %z')" "$*"; }
status() { printf '%s %s\n' "$(date '+%F %T %z')" "$*" > "$STATE/status"; log "$*"; }
if [ "${1:-}" != --manual ]; then
    hour=$(date +%H)
    if [ "$hour" -lt 2 ] || [ "$hour" -ge 5 ]; then log 'SKIP: outside 02:00–05:00'; exit 0; fi
fi
pmset -g batt | head -1 | grep -q "AC Power" || { log 'SKIP: battery power'; exit 0; }
# Also exclude simultaneous direct manual invocations. A stale lock fails closed.
mkdir "$STATE/lock" 2>/dev/null || { log 'SKIP: lock exists; another run or interrupted process'; exit 1; }
echo $$ > "$STATE/lock/pid"
tmp=$(mktemp -d "$STATE/run.XXXXXX") || { rm -rf "$STATE/lock"; exit 1; }
cleanup_needed=0
caf=''
field() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null; }
info() { diskutil info -plist "$1" > "$2" 2>/dev/null; }
running() { tmutil status 2>/dev/null | grep -Eq 'Running = 1;'; }
cleanup() {
    result=$?
    trap - EXIT INT TERM
    if [ "$cleanup_needed" = 1 ]; then
        if running; then
            status 'ATTENTION: backup still running; volume left mounted'
            result=1
        elif diskutil unmount "$UUID"; then
            if info "$UUID" "$tmp/after.plist" && [ -z "$(field "$tmp/after.plist" MountPoint)" ]; then
                log 'Time Machine volume is unmounted'
            else
                status 'ATTENTION: cannot confirm unmount'; result=1
            fi
        else
            status 'ATTENTION: unmount failed; do not disconnect'; result=1
        fi
    fi
    if info "$PERSONAL" "$tmp/personal.plist" && [ -n "$(field "$tmp/personal.plist" MountPoint)" ]; then
        log 'ATTENTION: personal volume remains mounted; eject it before disconnecting'
    fi
    [ -z "$caf" ] || kill "$caf" 2>/dev/null
    rm -rf "$tmp"
    rm -rf "$STATE/lock"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
info "$UUID" "$tmp/info.plist" || { status 'SKIP: backup disk absent or inaccessible'; exit 0; }
[ "$(field "$tmp/info.plist" VolumeUUID)" = "$UUID" ] && [ "$(field "$tmp/info.plist" Internal)" = false ] || { status 'ERROR: disk identity mismatch'; exit 1; }
running && { status 'SKIP: another backup is running'; exit 0; }
if [ "$(field "$tmp/info.plist" Locked)" = true ]; then
    log 'Unlocking Time Machine volume using System keychain'
    if ! security find-generic-password -a root -s local.nightly-time-machine.unlock -w /Library/Keychains/System.keychain |
        diskutil apfs unlockVolume "$UUID" -stdinpassphrase -nomount; then
        status 'ERROR: unattended unlock failed; run setup-unlock.sh and check keychain access'
        exit 1
    fi
fi
caffeinate -is -w $$ &
caf=$!
cleanup_needed=1
diskutil mount "$UUID" || { status 'ERROR: mount failed'; exit 1; }
info "$UUID" "$tmp/info.plist" || exit 1
mountpoint=$(field "$tmp/info.plist" MountPoint)
[ -n "$mountpoint" ] || { status 'ERROR: no mount point'; exit 1; }
# This also checks required Full Disk Access before starting the backup.
before=$(tmutil latestbackup -d "$mountpoint" 2>"$tmp/error") || {
    cat "$tmp/error"; status 'ERROR: cannot read existing backup; check Full Disk Access'; exit 1;
}
status 'BUSY: Time Machine backup running'
tmutil startbackup --block --destination "$DEST"
rc=$?
after=$(tmutil latestbackup -d "$mountpoint" 2>"$tmp/error") || {
    cat "$tmp/error"; status 'ERROR: cannot verify completed backup'; exit 1;
}
if [ "$rc" = 0 ] && [ -n "$after" ] && [ "$after" != "$before" ]; then
    printf '%s\n%s\n' "$(date '+%F %T %z')" "$after" > "$STATE/last-success"
    status 'SUCCESS: new completed backup verified; unmounting'
else
    status "ERROR: no new completed backup confirmed (tmutil exit $rc)"
    exit 1
fi
