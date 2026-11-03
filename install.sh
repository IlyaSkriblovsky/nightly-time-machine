#!/bin/bash
# Fresh installation only. Existing healthy installations need no migration.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
[ "$EUID" = 0 ] || { echo 'Run with sudo.'; exit 1; }
cd "$(dirname "$0")"
BASE=/Library/PrivilegedHelperTools/local.nightly-time-machine
APP="$BASE/Nightly Time Machine.app"
PLIST=/Library/LaunchDaemons/local.nightly-time-machine.plist
STATE=/var/db/local.nightly-time-machine
[ ! -e "$APP" ] && [ ! -L "$APP" ] || { echo 'Application already installed. No changes made; see README for updates.'; exit 1; }
[ ! -d "$STATE/lock" ] || { echo 'Backup lock exists; wait for completion.'; exit 1; }
[ ! -e "$PLIST" ] || { echo 'Existing service found. Refusing to replace it automatically.'; exit 1; }
codesign --verify --strict 'build/Nightly Time Machine.app'
plutil -lint app-daemon.plist
# Check conflicts before changing system settings.
if pmset -g sched | grep -qi 'Repeating power events'; then
    echo 'Existing repeat power schedule found; review it before a fresh installation.'
    exit 1
fi
for uuid in 89AD4B37-ACCB-4C87-8534-F0EF2885C3E3 C6E2B959-97F0-47B2-BFA3-1562924BC1FB; do
    if [ -f /etc/fstab ] && grep -q "$uuid" /etc/fstab; then
        grep -Fx "UUID=$uuid none apfs rw,noauto 0 0" /etc/fstab >/dev/null || { echo "Conflicting fstab entry: $uuid"; exit 1; }
    fi
done
install -d -o root -g wheel -m 755 "$BASE"
install -d -o root -g wheel -m 700 "$STATE"
if [ -f /etc/fstab ]; then cp -p /etc/fstab "$STATE/fstab.before-install"; fi
touch /etc/fstab
for uuid in 89AD4B37-ACCB-4C87-8534-F0EF2885C3E3 C6E2B959-97F0-47B2-BFA3-1562924BC1FB; do
    if ! grep -q "$uuid" /etc/fstab; then
        printf '\nUUID=%s none apfs rw,noauto 0 0\n' "$uuid" >> /etc/fstab
    fi
done
ditto 'build/Nightly Time Machine.app' "$APP"
chown -R root:wheel "$APP"
chmod -R go-w "$APP"
codesign --verify --strict "$APP"
install -o root -g wheel -m 644 app-daemon.plist "$PLIST"
pmset repeat wake MTWRFSU 01:58:00
launchctl bootstrap system "$PLIST"
echo 'Installed. Configure the key with sudo -H ./setup-unlock.sh, grant the app Full Disk Access, then sudo ./test-service.sh.'
