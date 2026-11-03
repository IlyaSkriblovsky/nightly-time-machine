#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
[ "$EUID" = 0 ] || { echo 'Run with sudo.'; exit 1; }
# sudo can retain the caller's HOME. security's user domain follows HOME,
# so use sudo's supported -H mode before touching root's keychain preferences.
if [ "$(stat -f %u "${HOME:?}" 2>/dev/null || true)" != 0 ]; then
    if [ "${NIGHTLY_TM_ROOT_REEXEC:-}" = 1 ]; then
        echo 'Root home directory is unavailable. Run with sudo -H.'
        exit 1
    fi
    exec /usr/bin/sudo -H /usr/bin/env NIGHTLY_TM_ROOT_REEXEC=1 /bin/bash "$0" "$@"
fi
cd "$(dirname "$0")"
UUID=89AD4B37-ACCB-4C87-8534-F0EF2885C3E3
SERVICE=local.nightly-time-machine.unlock
KEYCHAIN=/Library/Keychains/System.keychain
case "${1:-}" in
    ''|--verify-existing) ;;
    *) echo 'Usage: setup-unlock.sh [--verify-existing]'; exit 2 ;;
esac
if [ -d /var/db/local.nightly-time-machine/lock ]; then
    echo 'Backup lock exists. Wait for the running backup before updating.'
    exit 1
fi
if [ "${1:-}" != --verify-existing ]; then
echo 'Enter the encryption password for Mac Backup (not your Mac login password).'
echo 'It will be saved in System keychain; input is hidden.'
# With -w last, security cannot also accept an explicit keychain path.
# Temporarily select System as root's default, restoring it even on failure.
original=''
if default_result=$(security default-keychain -d user 2>&1); then
    original=${default_result#*\"}
    original=${original%\"*}
    [ -n "$original" ] || { echo 'Unexpected empty default keychain path.'; exit 1; }
elif [[ "$default_result" == *'A default keychain could not be found.'* ]]; then
    echo 'Root has no default keychain; using System temporarily.'
else
    printf '%s\n' "$default_result" >&2
    exit 1
fi
restore_default() {
    if [ -n "$original" ]; then
        security default-keychain -d user -s "$original"
    else
        security default-keychain -d user -s
    fi
}
security default-keychain -d user -s "$KEYCHAIN"
trap restore_default EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
security add-generic-password -U -a root -s "$SERVICE" \
    -l 'Nightly Time Machine — Mac Backup' \
    -T /usr/bin/security -w
restore_default
trap - EXIT INT TERM
fi
echo 'Checking the saved password without mounting the volume...'
security find-generic-password -a root -s "$SERVICE" -w "$KEYCHAIN" |
    diskutil apfs unlockVolume "$UUID" -user "$UUID" -stdinpassphrase -verify
echo 'Saved key verified. Application and schedule were not changed.'
