#!/bin/zsh
# Auto backup: `lazymac --schedule` (the same code as the settings window) must write the schedule into
# local.lazymac-daily.plist, keep the plist's other keys, reload the job, and refuse while a backup runs.
# Runs against a temporary LaunchAgents folder and a fake launchctl, so this Mac's real job is not touched.
# Usage: tests/app-schedule.sh   (builds the app with swift build first)
set -euo pipefail
REPO=${0:A:h:h}
cd "$REPO/app"
swift build -q
BIN=$(swift build --show-bin-path)/lazymac
mkdir -p "$REPO/.work"
TMP=$(mktemp -d "$REPO/.work/app-schedule.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
export LAZYMAC_DATA=$TMP/data LAZYMAC_STORAGE_CONF=$TMP/storage.conf
export LAZYMAC_LAUNCHAGENTS_DIR=$TMP/agents LAZYMAC_LAUNCHCTL=$TMP/launchctl
print -r -- "#!/bin/zsh
print -r -- \"\$*\" >> $TMP/calls
[[ \$1 == print && -f $TMP/running ]] && print 'state = running'
exit 0" > $TMP/launchctl
chmod +x $TMP/launchctl
P=$TMP/agents/local.lazymac-daily.plist
fail=0
check() { if eval "$2"; then print "ok      $1"; else print "FAIL    $1"; fail=1; fi; }
cal() { plutil -extract StartCalendarInterval json -o - $P; }

check "off when there is no plist" "[[ \$($BIN --schedule show) == off ]]"
$BIN --schedule daily:04:00 --repo $REPO >/dev/null
check "daily 04:00 writes one calendar entry and loads it" \
  "[[ \$(cal) == '{\"Hour\":4,\"Minute\":0}' ]] && grep -q \"bootstrap gui/\$(id -u) $P\" $TMP/calls"
check "a fresh plist starts bin/daily.sh through bun" "plutil -extract ProgramArguments.2 raw -o - $P | grep -q 'bin/daily.sh'"
key() { plutil -extract $1 raw -o - $P; }
check "it starts at login and every 30 minutes with --if-due, so missed backups catch up" \
  "[[ \$(key RunAtLoad) == true && \$(key StartInterval) == 1800 ]] && key ProgramArguments.2 | grep -q 'daily.sh. --if-due\$'"
plutil -insert Marker -string keep-me $P
$BIN --schedule every:6:01:30 --repo $REPO >/dev/null
check "every 6 hours from 01:30 is four entries" \
  "[[ \$(cal) == '[{\"Hour\":1,\"Minute\":30},{\"Hour\":7,\"Minute\":30},{\"Hour\":13,\"Minute\":30},{\"Hour\":19,\"Minute\":30}]' ]]"
check "changing the schedule keeps the plist's other keys" "[[ \$(plutil -extract Marker raw -o - $P) == keep-me ]]"
check "and keeps the catch-up keys, --if-due only once" \
  "[[ \$(key StartInterval) == 1800 && \$(key ProgramArguments.2 | grep -o -- --if-due | wc -l) -eq 1 ]]"
check "show reads it back as on" "[[ \$($BIN --schedule show) == on\$'\\t'* ]]"
$BIN --schedule weekly:0:09:15 >/dev/null
check "weekly Sunday 09:15" "[[ \$(cal) == '{\"Hour\":9,\"Minute\":15,\"Weekday\":0}' ]]"
$BIN --schedule hourly:45 >/dev/null
check "hourly at :45" "[[ \$(cal) == '{\"Minute\":45}' ]]"
set +e; $BIN --schedule every:5 2>/dev/null; c1=$?; $BIN --schedule daily:25:00 2>/dev/null; c2=$?; set -e
check "a bad schedule stops with exit 2" "[[ $c1 == 2 && $c2 == 2 ]]"
touch $TMP/running
set +e; $BIN --schedule daily:05:00 >/dev/null 2>&1; c=$?; set -e
check "a running backup is not interrupted (exit 1, schedule unchanged)" "[[ $c == 1 && \$(cal) == '{\"Minute\":45}' ]]"
rm $TMP/running
cp $REPO/tests/fixtures/older-daily.plist $P
: > $TMP/calls
$BIN --schedule upgrade >/dev/null
check "a job from an older LazyMac gets the catch-up keys and is reloaded" \
  "[[ \$(key RunAtLoad) == true && \$(key StartInterval) == 1800 && \$(key AssociatedBundleIdentifiers.0) == com.floweredao.lazymac ]] && key ProgramArguments.2 | grep -q 'daily.sh --if-due\$' && grep -q '^bootstrap' $TMP/calls"
: > $TMP/calls
$BIN --schedule upgrade >/dev/null
check "an up-to-date job is left alone" "[[ ! -s $TMP/calls ]]"
$BIN --schedule off >/dev/null
check "off unloads the job and removes the plist" "[[ ! -e $P ]] && tail -1 $TMP/calls | grep -q '^bootout gui/'"
exit $fail
