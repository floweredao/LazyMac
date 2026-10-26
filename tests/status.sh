#!/bin/zsh
# The Status card (`lazymac --backup-status`) must tell the same story as bin/due.sh: up to date, missed (with the
# slot), waiting after a failure, waiting for the internet or a free connection, paused, off, the next time and the
# last problem. Fake clock and state under .work/; this Mac's job is not touched.
# Usage: tests/status.sh   (builds the app with swift build first)
set -euo pipefail
REPO=${0:A:h:h}
cd "$REPO/app"
swift build -q
BIN=$(swift build --show-bin-path)/lazymac
mkdir -p "$REPO/.work"
TMP=$(mktemp -d "$REPO/.work/status.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
export LAZYMAC_STATE=$TMP/state LAZYMAC_LAUNCHAGENTS_DIR=$TMP/agents LAZYMAC_DAILY_LOGDIR=$TMP/logs
export LAZYMAC_DATA=$TMP/data LAZYMAC_STORAGE_CONF=$TMP/storage.conf
mkdir -p $TMP/agents $TMP/logs
source "$REPO/bin/due.sh"
fail=0
check() { if eval "$2"; then print "ok      $1"; else print "FAIL    $1"; fail=1; fi; }
at() { strftime -r '%Y-%m-%d %H:%M' "$1"; }
st() { LAZYMAC_NOW=$(at "$1") $BIN --backup-status; }
phase() { st "$1" | sed -n 's/^phase //p'; }
reset() { rm -f $LAZYMAC_STATE; }

check "no schedule: off" "[[ \$(phase '2026-10-26 10:00') == off ]]"
print -r -- '{"StartCalendarInterval":{"Hour":4,"Minute":0}}' > $TMP/p.json
plutil -convert xml1 -o $DUE_PLIST $TMP/p.json

reset; state_set last-success $(at "2026-10-26 04:05")
check "today's backup is done: up to date, next is tomorrow 04:00" \
  "[[ \$(phase '2026-10-26 10:00') == uptodate ]] && st '2026-10-26 10:00' | grep -qx \"next \$(at '2026-10-27 04:00')\""
reset; state_set last-success $(at "2026-10-23 04:05")
check "three days off: missed, naming today's 04:00 slot" "[[ \$(phase '2026-10-26 10:00') == \"missed \$(at '2026-10-26 04:00')\" ]]"
check "and due.sh agrees a backup is due" "[[ \$(LAZYMAC_NOW=\$(at '2026-10-26 10:00') due_decide) == run ]]"
reset; state_set last-success $(at "2026-10-26 03:30")
check "a catch-up at 03:30 counts for the 04:00 slot (half-day rule), like due.sh" \
  "[[ \$(phase '2026-10-26 04:30') == uptodate && \$(LAZYMAC_NOW=\$(at '2026-10-26 04:30') due_decide) == recent ]]"
reset; state_set last-success $(at "2026-10-25 04:05"); state_set failures 2; state_set last-attempt $(at "2026-10-26 10:00")
check "two failures: waiting until 10:30 to try again, like due.sh" \
  "[[ \$(phase '2026-10-26 10:10') == \"retrying \$(at '2026-10-26 10:30')\" && \$(LAZYMAC_NOW=\$(at '2026-10-26 10:10') due_decide) == wait ]]"
check "after the wait it is just missed again" "[[ \$(phase '2026-10-26 10:31') == missed* ]]"
state_set failures; state_set deferred offline
check "offline: waiting for the internet" "[[ \$(phase '2026-10-26 10:31') == 'waiting offline' ]]"
state_set deferred metered
check "metered without the option: missed, not waiting" "[[ \$(phase '2026-10-26 10:31') == missed* ]]"
state_set metered wait
check "metered with the option: waiting for a free connection" "[[ \$(phase '2026-10-26 10:31') == 'waiting metered' ]]"
state_set paused 1
check "paused wins over everything else" "[[ \$(phase '2026-10-26 10:31') == paused ]]"
reset
print -r -- "$(date '+%F') 04:00:01 === start (pid 1, file backup off)
$(date '+%F') 04:00:03 FAIL: The backup disk Example is not connected. Connect it and try again." > $TMP/logs/$(date +%F).log
check "the last failure's reason is shown" "st '2026-10-26 10:00' | grep -qx 'problem The backup disk Example is not connected. Connect it and try again.'"
exit $fail
