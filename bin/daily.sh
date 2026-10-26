#!/bin/zsh
# Daily backup of this Mac's programs and setup: scan the apps and tools, update the list (main Mac only),
# save the settings files (main Mac only), and copy the data folder to storage. Only the main Mac changes
# shared files; every Mac owns its scan. Folder backup is opt-in through "files on" in storage.conf.
# Each stage is logged as "step <name>" (refresh, scan, list, settings, copy, folders); the app shows them.
# Usage: daily.sh [--if-due]. The LaunchAgent passes --if-due: it backs up only when bin/due.sh says a backup is due
# and the Mac can reach the backup place, and otherwise ends quietly. While backups are paused every run stops at the
# next step and logs "=== paused". Only one backup runs at a time (an fcntl lock on backup.lock in the log folder).
set -u
IF_DUE=0
[[ " $* " == *" --if-due "* ]] && IF_DUE=1
export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:$HOME/.bun/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export LC_ALL=en_US.UTF-8
REPO=${0:A:h:h}
source "$REPO/bin/storage.sh"
LOGDIR=${LAZYMAC_DAILY_LOGDIR:-$HOME/Library/Logs/lazymac-daily}
LOCKFILE=$LOGDIR/backup.lock
PIDFILE=$LOGDIR/backup.pid
CONF=${LAZYMAC_BACKUP_CONF:-$HOME/Library/Application Support/lazymac/backup.conf}
HOOKS=${LAZYMAC_HOOKS:-$HOME/.config/lazymac/hooks}
REMOTE=()
[[ -n ${LAZYMAC_DAILY_REMOTE:-} ]] && REMOTE=("$LAZYMAC_DAILY_REMOTE")
source "$REPO/bin/due.sh"
mkdir -p "$LOGDIR"
LOG=$LOGDIR/$(date +%F).log
log() { print -r -- "$(date '+%F %T') $*" >> "$LOG"; }
stop_if_paused() { due_paused || return 0; log "=== paused"; exit 0; }
step() { stop_if_paused; log "step $1"; }
notify() {
  if [[ -n ${LAZYMAC_DAILY_NOTIFY_FILE:-} ]]; then
    print -r -- "$1" >> "$LAZYMAC_DAILY_NOTIFY_FILE"
  elif [[ -x $HOOKS/on-failure ]]; then
    "$HOOKS/on-failure" "$1" || log "on-failure hook failed"
  else
    osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "LazyMac"' -e 'end run' \
      "$1" >/dev/null 2>&1
  fi
}
# A step that fails because backups were paused meanwhile is a pause, not a failure. Automatic runs report a failure
# once per bad stretch (bin/due.sh due_alert); a run someone started reports every failure.
fail() {
  stop_if_paused
  log "FAIL: $1"
  if (( IF_DUE )); then
    due_failed
    local alert=$(due_alert failed "$1")
    [[ -z $alert ]] || notify "$alert"
  else
    notify "The daily backup failed: $1"
  fi
  exit 1
}

if due_paused; then
  if (( ! IF_DUE )) || due_defer paused; then log "skip: paused"; fi
  exit 0
fi
if (( IF_DUE )); then
  [[ $(due_decide) == run ]] || exit 0
fi
zmodload zsh/system
[[ -e $LOCKFILE ]] || : >> "$LOCKFILE"
if ! zsystem flock -t 0 -f LOCKFD "$LOCKFILE" 2>/dev/null; then
  pid=$(cat "$PIDFILE" 2>/dev/null)
  if (( IF_DUE )); then log "skip: running (pid $pid)"; exit 0; fi
  fail "Another backup is still running (pid $pid)"
fi
print $$ > "$PIDFILE"
if (( IF_DUE )); then
  wait=$(due_wake_wait)
  if (( wait > 0 )); then log "wait ${wait}s after waking up"; sleep $wait; fi
  if [[ $BACKEND != local ]]; then
    net=$(due_network)
    if [[ $net == offline ]] || [[ $net == metered && $(state_get metered) == wait ]]; then
      due_defer $net && log "skip: $net"
      alert=$(due_alert $net)
      [[ -z $alert ]] || notify "$alert"
      exit 0
    fi
  fi
  due_power_ok || exit 0
  due_started
fi
exec >> "$LOG" 2>&1
folder_backup() {
  step folders
  log "backup -> ${LAZYMAC_DAILY_REMOTE:-$STORAGE_TARGET}"
  zsh "$REPO/bin/nogit-backup.sh" rclone "${REMOTE[@]}" || fail "Folder copy failed"
  log "check -> ${LAZYMAC_DAILY_REMOTE:-$STORAGE_TARGET}"
  zsh "$REPO/bin/nogit-backup.sh" rclone "${REMOTE[@]}" --check || fail "Folder comparison failed"
}
log "=== start (pid $$, file backup $FILES)"
[[ ! -x $HOOKS/before-daily ]] || "$HOOKS/before-daily" || log "before-daily hook failed (continuing)"
# Stop early, with the reason, when the backup place or a needed tool is missing.
why=$(storage_valid 2>&1) || fail "$why"
command -v gitleaks >/dev/null || fail "gitleaks is not installed"
[[ $STORAGE_ROLE != main ]] || command -v bun >/dev/null || fail "bun is not installed"

# The main Mac is authoritative for shared files. Download others' scans without
# overwriting local edits; secondary Macs refresh the main Mac's shared files.
step refresh
if [[ $STORAGE_ROLE != main ]]; then
  storage_data download || fail "Could not restore shared data from storage"
elif [[ $BACKEND == local && -d $STORAGE_TARGET/inventory ]]; then
  mkdir -p "$DATA/inventory"
  rsync -a --checksum --exclude="/$STORAGE_HOST/***" "$STORAGE_TARGET/inventory/" "$DATA/inventory/" || fail "Could not refresh inventories"
elif [[ $BACKEND == gdrive ]]; then
  rclone copy --exclude "/inventory/$STORAGE_HOST/**" --include '/inventory/**' --exclude '*' \
    "$STORAGE_TARGET" "$DATA" || fail "Could not refresh inventories"
fi
[[ -f $DATA/catalog.tsv ]] || fail "Initialize the data folder in LazyMac first"
step scan
zsh "$REPO/bin/scan.sh" --no-push || fail "Inventory scan failed"
if [[ $STORAGE_ROLE == main ]]; then
  step list
  bun "$REPO/bin/catalog.ts" prune || fail "Catalog prune refused"
  bun "$REPO/bin/catalog.ts" render || fail "Catalog render failed"
  bun "$REPO/bin/snapshot.ts" take || fail "Snapshot failed"
  if [[ " ${LAZYMAC_DAILY_SKIP:-} " != *" settings "* ]]; then
    step settings
    zsh "$REPO/bin/settings.sh" save || fail "Could not save the settings files"
  fi
fi
step copy
storage_data upload || fail "Could not copy data to storage"
if [[ $FILES == on && " ${LAZYMAC_DAILY_SKIP:-} " != *" backup "* ]]; then
  if [[ $STORAGE_ROLE == main ]]; then
    [[ -f $CONF ]] || fail "Set up folders in LazyMac first"
    folder_backup
  elif [[ -f $CONF ]] && grep -q '^[[:space:]]*folder[[:space:]]' "$CONF"; then
    folder_backup
  fi
fi
find "$LOGDIR" -name '*.log' -mtime +30 -delete
due_succeeded
log "=== ok"
