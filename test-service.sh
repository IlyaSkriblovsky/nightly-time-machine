#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
[ "$EUID" = 0 ] || { echo 'Run with sudo.'; exit 1; }
STATE=/var/db/local.nightly-time-machine
[ ! -d "$STATE/lock" ] || { echo 'A backup lock exists; do not start a second run.'; exit 1; }
launchctl print system/local.nightly-time-machine | grep -F '/Library/PrivilegedHelperTools/local.nightly-time-machine/Nightly Time Machine.app/Contents/MacOS/NightlyTimeMachine' >/dev/null || { echo 'Install the application service first.'; exit 1; }
install -d -o root -g wheel -m 700 "$STATE"
install -o root -g wheel -m 600 /dev/null "$STATE/run-once-manual"
if ! launchctl kickstart system/local.nightly-time-machine; then
    rm -f "$STATE/run-once-manual"
    exit 1
fi
echo 'Requested one daytime run through the real system service. Schedule unchanged.'
echo 'Watch: tail -f /var/log/local.nightly-time-machine.log'
