#!/bin/zsh
# Catch-up rules (bin/due.sh) and how daily.sh --if-due follows them: one backup however many times were missed,
# no second backup within half a period, waiting after failures, pause, the backup lock, offline and metered
# connections, and one alert per bad stretch. Fake clock, network and data under .work/; this Mac's job is not touched.
# Usage: tests/due.sh
set -euo pipefail
REPO=${0:A:h:h}
mkdir -p "$REPO/.work"
TMP=$(mktemp -d "$REPO/.work/due.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
export LAZYMAC_STATE=$TMP/state LAZYMAC_LAUNCHAGENTS_DIR=$TMP/agents LAZYMAC_LANG=en
source "$REPO/bin/due.sh"
fail=0
check() { if eval "$2"; then print "ok      $1"; else print "FAIL    $1"; fail=1; fi; }
schedule() {
  mkdir -p $TMP/agents
  print -r -- "{\"StartCalendarInterval\":$1}" > $TMP/p.json
  plutil -convert xml1 -o $DUE_PLIST $TMP/p.json
}
at() { strftime -r '%Y-%m-%d %H:%M' "$1"; }
reset() { rm -f $LAZYMAC_STATE; }
decide_at() { LAZYMAC_NOW=$(at "$1") due_decide; }

schedule '{"Hour":4,"Minute":0}'
reset; state_set last-success $(at "2026-10-25 04:05")
check "on time: the 04:00 slot is due when the last backup was yesterday" "[[ \$(decide_at '2026-10-26 04:00') == run ]]"
check "not due again after today's slot is done" "state_set last-success \$(at '2026-10-26 04:05'); [[ \$(decide_at '2026-10-26 10:00') == notdue ]]"
reset; state_set last-success $(at "2026-10-23 04:05")
check "a Mac that was off for three slots is due once" "[[ \$(decide_at '2026-10-26 10:00') == run ]]"
LAZYMAC_NOW=$(at "2026-10-26 10:00") due_succeeded
check "and after that one backup nothing more is due that day" "[[ \$(decide_at '2026-10-26 23:59') == notdue ]]"
reset; state_set last-success $(at "2026-10-26 03:30")
check "a catch-up at 03:30 skips the 04:00 slot (less than half a day)" "[[ \$(decide_at '2026-10-26 04:00') == recent ]]"
check "the next day's slot runs at its usual time" "[[ \$(decide_at '2026-10-27 04:00') == run ]]"
reset; state_set last-success $(at "2026-10-25 17:00")
check "a catch-up at 17:00 waits past 04:00 until half a day has passed" \
  "[[ \$(decide_at '2026-10-26 04:30') == recent && \$(decide_at '2026-10-26 05:00') == run ]]"
check "the first backup ever is due" "reset; [[ \$(decide_at '2026-10-26 10:00') == run ]]"

reset; state_set failures 1; state_set last-attempt $(at "2026-10-26 10:00")
check "after one failure it waits 15 minutes" "[[ \$(decide_at '2026-10-26 10:14') == wait && \$(decide_at '2026-10-26 10:15') == run ]]"
state_set failures 3
check "after three failures it waits an hour" "[[ \$(decide_at '2026-10-26 10:59') == wait && \$(decide_at '2026-10-26 11:00') == run ]]"
state_set failures 9
check "the wait never grows past two hours" "[[ \$(decide_at '2026-10-26 11:59') == wait && \$(decide_at '2026-10-26 12:00') == run ]]"
schedule '{"Minute":0}'
check "nor past one period (hourly: one hour)" "[[ \$(decide_at '2026-10-26 11:00') == run ]]"
schedule '{"Hour":4,"Minute":0}'

reset; state_set paused 1
check "paused: nothing is due" "[[ \$(decide_at '2026-10-26 10:00') == paused ]]"
reset
check "60 s after waking it waits the rest of the minute" \
  "[[ \$(LAZYMAC_NOW=1000 LAZYMAC_WAKETIME=980 due_wake_wait) == 40 && \$(LAZYMAC_NOW=1000 LAZYMAC_WAKETIME=900 due_wake_wait) == 0 ]]"
check "no schedule: a run is due" "mv $DUE_PLIST $TMP/off.plist; [[ \$(decide_at '2026-10-26 10:00') == run ]]; mv $TMP/off.plist $DUE_PLIST"

due() { zsh "$REPO/bin/due.sh" "$@"; }
check "a metered connection backs up unless waiting was turned on" "[[ \$(LAZYMAC_NET=metered due net) == run ]]"
state_set metered wait
check "with waiting on, a metered connection waits" "[[ \$(LAZYMAC_NET=metered due net | head -1) == 'skip metered' ]]"
check "a free connection still backs up" "[[ \$(LAZYMAC_NET=free due net) == run ]]"
check "offline always waits" "[[ \$(LAZYMAC_NET=offline due net | head -1) == 'skip offline' ]]"

reset; export LAZYMAC_NOW=$(at "2026-10-26 10:00")
state_set last-success $(at "2026-10-25 04:05")
check "first and second failures stay quiet" "[[ -z \$(due fail boom) && -z \$(due fail boom) ]]"
check "the third failure in a row alerts once" "[[ \$(due fail boom) == *'failed 3 times in a row: boom'* && -z \$(due fail boom) ]]"
due ok
check "a success ends the stretch" "[[ -z \$(state_get notified) && -z \$(state_get failures) ]]"
reset; state_set last-success $(at "2026-10-23 04:05")
check "offline for more than two days alerts once" \
  "[[ \$(LAZYMAC_NET=offline due net | tail -1) == 'No backup for 3 days.'* && \$(LAZYMAC_NET=offline due net | wc -l) -eq 1 ]]"
reset; state_set last-success $(at "2026-10-23 04:05"); state_set metered wait
check "metered: the alert says it can be backed up now, in Korean on a Korean Mac" \
  "[[ \$(LAZYMAC_LANG=ko LAZYMAC_NET=metered due net | tail -1) == *'지금 백업할 수 있어요'* ]]"
unset LAZYMAC_NOW

# daily.sh --if-due with a local backup place (no network check).
source "$REPO/tests/fixtures.zsh"
seed_data
export HOME=$TMP/home LAZYMAC_BACKUP_CONF=$TMP/backup.conf RCLONE_CONFIG=$TMP/rclone.conf
export LAZYMAC_DAILY_LOGDIR=$TMP/logs LAZYMAC_DAILY_NOTIFY_FILE=$TMP/notified LAZYMAC_HOOKS=$TMP/hooks
mkdir -p $HOME/.bun/bin $LAZYMAC_HOOKS
ln -s "$(command -v bun)" $HOME/.bun/bin/bun
seed_inventory $TMP/scan
export LAZYMAC_INVENTORY_SCRIPT=$TMP/inventory.sh
printf '#!/bin/zsh\nmkdir -p "$1"\ncp -R "%s/." "$1/"\n' $TMP/scan > $LAZYMAC_INVENTORY_SCRIPT
LOG=$TMP/logs/$(date +%F).log
daily() { zsh "$REPO/bin/daily.sh" "$@"; }
lines() { grep -c -- "$1" $LOG 2>/dev/null || true; }

reset; state_set paused 1
daily --if-due; daily --if-due
check "paused: automatic runs end quietly and log it once" "[[ \$(lines 'skip: paused') == 1 && \$(lines '=== start') == 0 ]]"
daily
check "paused: a run started by hand does not back up either" "[[ \$(lines 'skip: paused') == 2 && \$(lines '=== start') == 0 ]]"

reset
mkfifo $TMP/ready $TMP/go
: >> $TMP/logs/backup.lock
zsh -c 'zmodload zsh/system; zsystem flock -f fd "$1"; print -r -- $$ > "$2"; print locked > "$3"; read -r < "$4"' \
  _ $TMP/logs/backup.lock $TMP/logs/backup.pid $TMP/ready $TMP/go &
holder=$!
read -r < $TMP/ready
set +e; daily --if-due; c1=$?; daily; c2=$?; set -e
check "while another backup holds the lock, an automatic run skips quietly" "[[ $c1 == 0 && \$(lines 'skip: running (pid $holder)') == 1 ]]"
check "and a run started by hand says another backup is running" "[[ $c2 == 1 && \$(lines 'FAIL: Another backup is still running') == 1 ]]"
print go > $TMP/go
wait $holder

reset; rm -f $TMP/notified
print -r -- "#!/bin/zsh
print paused 1 >> $LAZYMAC_STATE" > $LAZYMAC_HOOKS/before-daily
chmod +x $LAZYMAC_HOOKS/before-daily
set +e; daily --if-due; c=$?; set -e
check "pausing during a backup stops it at the next step, not as a failure" \
  "[[ $c == 0 && \$(lines '=== paused') == 1 && \$(lines 'step ') == 0 && -z \$(state_get failures) && ! -e $TMP/notified ]]"
rm $LAZYMAC_HOOKS/before-daily

reset
cp $LAZYMAC_STORAGE_CONF $TMP/storage.conf.real
printf 'backend local\nlocal /Volumes/LazyMac-Test-Disk-%s/backup\nfiles off\ndata %s\n' $$ "$LAZYMAC_DATA" > $LAZYMAC_STORAGE_CONF
for i in 1 2 3; do
  set +e; LAZYMAC_NOW=$(( EPOCHSECONDS + i * 3 * 3600 )) daily --if-due; set -e
done
check "a backup disk that is not connected: three failed automatic runs, one alert" \
  "[[ \$(state_get failures) == 3 && \$(wc -l < $TMP/notified) -eq 1 ]] && grep -q 'failed 3 times in a row: The backup disk' $TMP/notified"
mv $TMP/storage.conf.real $LAZYMAC_STORAGE_CONF

reset
set +e; daily --if-due; c=$?; set -e
check "a due automatic run backs up and records the success" "[[ $c == 0 && -n \$(state_get last-success) ]] && tail -1 $LOG | grep -q '=== ok'"
before=$(wc -l < $LOG)
daily --if-due
check "the next automatic start is not due and leaves no log line" "(( \$(wc -l < $LOG) == $before ))"
exit $fail
