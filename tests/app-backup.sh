#!/bin/zsh
# A Mac with no LazyMac repo: the schedule must run this app's own `lazymac --run-backup`, which copies the folders
# in backup.conf, compares, logs, and reports a failure. Uses a temporary LaunchAgents folder, a fake launchctl and a
# local folder standing in for the cloud, so this Mac's real job and Drive are not touched.
# Usage: tests/app-backup.sh   (builds the app with swift build first; needs rclone)
set -euo pipefail
REPO=${0:A:h:h}
cd "$REPO/app"
swift build -q
BIN=$(swift build --show-bin-path)/lazymac
mkdir -p "$REPO/.work"
TMP=$(mktemp -d "$REPO/.work/app-backup.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
export HOME=$TMP/home LAZYMAC_DATA=$TMP/data LAZYMAC_STORAGE_CONF=$TMP/storage.conf
mkdir -p "$HOME"
export LAZYMAC_REPO=none LAZYMAC_LAUNCHAGENTS_DIR=$TMP/agents LAZYMAC_LAUNCHCTL=$TMP/launchctl
export LAZYMAC_BACKUP_CONF=$TMP/conf/backup.conf LAZYMAC_BACKUP_SCRIPT=$REPO/bin/nogit-backup.sh
export LAZYMAC_DAILY_LOGDIR=$TMP/logs LAZYMAC_DAILY_NOTIFY_FILE=$TMP/notified RCLONE_CONFIG=$TMP/rclone.conf
print -r -- '#!/bin/zsh
exit 0' > $TMP/launchctl
chmod +x $TMP/launchctl
fail=0
check() { if eval "$2"; then print "ok      $1"; else print "FAIL    $1"; fail=1; fi; }

mkdir -p $TMP/conf $TMP/src/a $TMP/cloud
print hi > $TMP/src/a/f.txt
print -r -- "remote :local:$TMP/cloud
folder $TMP/src/a" > $LAZYMAC_BACKUP_CONF
printf 'backend gdrive\nremote :local:%s\nfiles on\n' "$TMP/cloud" > "$LAZYMAC_STORAGE_CONF"

$BIN --schedule daily:03:30 >/dev/null
P=$TMP/agents/local.lazymac-daily.plist
check "without a repo the job runs this app with --run-backup" \
  "[[ \$(plutil -extract ProgramArguments.0 raw -o - $P) == $BIN && \$(plutil -extract ProgramArguments.1 raw -o - $P) == --run-backup ]]"

set +e; $BIN --run-backup; c=$?; set -e
check "--run-backup copies and compares (exit 0)" "[[ $c == 0 && -f $TMP/cloud/_root$TMP/src/a/f.txt ]]"
check "it logs the run and ends with ok" "grep -q '=== ok' $TMP/logs/*.log"
check "nothing was reported" "[[ ! -e $TMP/notified ]]"

print -r -- "remote :local:$TMP/cloud
folder $TMP/src/gone" > $LAZYMAC_BACKUP_CONF
set +e; $BIN --run-backup; c=$?; set -e
check "a failed run exits 1, logs FAIL and reports one line" \
  "[[ $c == 1 ]] && grep -q 'FAIL: backup' $TMP/logs/*.log && [[ \$(wc -l < $TMP/notified) -eq 1 ]]"
exit $fail
