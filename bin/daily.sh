#!/bin/zsh
# Daily data sync. Only the main Mac changes shared files; every Mac owns its scan.
# Folder backup is opt-in through "files on" in storage.conf.
set -u
export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:$HOME/.bun/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export LC_ALL=en_US.UTF-8
REPO=${0:A:h:h}
source "$REPO/bin/storage.sh"
LOGDIR=${LAZYMAC_DAILY_LOGDIR:-$HOME/Library/Logs/lazymac-daily}
LOCK=$LOGDIR/run.lock
CONF=${LAZYMAC_BACKUP_CONF:-$HOME/Library/Application Support/lazymac/backup.conf}
HOOKS=${LAZYMAC_HOOKS:-$HOME/.config/lazymac/hooks}
REMOTE=()
[[ -n ${LAZYMAC_DAILY_REMOTE:-} ]] && REMOTE=("$LAZYMAC_DAILY_REMOTE")
mkdir -p "$LOGDIR"
LOG=$LOGDIR/$(date +%F).log
exec >> "$LOG" 2>&1
log() { print -r -- "$(date '+%F %T') $*"; }
owned=0
release() { (( owned )) && rm -rf "$LOCK"; owned=0; }
trap release EXIT
fail() {
  log "FAIL: $1"
  if [[ -n ${LAZYMAC_DAILY_NOTIFY_FILE:-} ]]; then
    print -r -- "$1" >> "$LAZYMAC_DAILY_NOTIFY_FILE"
  elif [[ -x $HOOKS/on-failure ]]; then
    "$HOOKS/on-failure" "$1" || log "on-failure hook failed"
  else
    osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "LazyMac"' -e 'end run' \
      "The daily backup failed: $1" >/dev/null 2>&1
  fi
  exit 1
}
folder_backup() {
  log "backup -> ${LAZYMAC_DAILY_REMOTE:-$STORAGE_TARGET}"
  zsh "$REPO/bin/nogit-backup.sh" rclone "${REMOTE[@]}" || fail "Folder copy failed"
  log "check -> ${LAZYMAC_DAILY_REMOTE:-$STORAGE_TARGET}"
  zsh "$REPO/bin/nogit-backup.sh" rclone "${REMOTE[@]}" --check || fail "Folder comparison failed"
}
if ! mkdir "$LOCK" 2>/dev/null; then
  pid=$(cat "$LOCK/pid" 2>/dev/null)
  [[ -z $pid ]] || ! kill -0 "$pid" 2>/dev/null || fail "Another backup is still running (pid $pid)"
  rm -rf "$LOCK"; mkdir "$LOCK" || fail "Could not acquire backup lock"
fi
owned=1; print $$ > "$LOCK/pid"
log "=== start (pid $$, file backup $FILES)"
[[ ! -x $HOOKS/before-daily ]] || "$HOOKS/before-daily" || log "before-daily hook failed (continuing)"

# The main Mac is authoritative for shared files. Download others' scans without
# overwriting local edits; secondary Macs refresh the main Mac's shared files.
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
log "scan"
zsh "$REPO/bin/scan.sh" --no-push || fail "Inventory scan failed"
if [[ $STORAGE_ROLE == main ]]; then
  log "prune"
  bun "$REPO/bin/catalog.ts" prune || fail "Catalog prune refused"
  bun "$REPO/bin/catalog.ts" render || fail "Catalog render failed"
  bun "$REPO/bin/snapshot.ts" take || fail "Snapshot failed"
fi
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
log "=== ok"
