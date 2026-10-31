#!/bin/zsh
# Real local copies under .work/, no cloud credentials or real user data.
set -euo pipefail
REPO=${0:A:h:h}
mkdir -p "$REPO/.work"
TMP=$(mktemp -d "$REPO/.work/storage.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
source "$REPO/tests/fixtures.zsh"
seed_data
export HOME=$TMP/home LAZYMAC_BACKUP_CONF=$TMP/backup.conf RCLONE_CONFIG=$TMP/rclone.conf
export LAZYMAC_DAILY_LOGDIR=$TMP/logs LAZYMAC_DAILY_NOTIFY_FILE=$TMP/notified LAZYMAC_HOOKS=$TMP/hooks
mkdir -p "$HOME/Documents/my notes/node_modules" "$TMP/storage/retained"
printf 'hello\n' > "$HOME/Documents/my notes/file.txt"
touch -t 202001010000 "$HOME/Documents/my notes/file.txt"
printf 'private\n' > "$HOME/Documents/my notes/.env"
printf 'example\n' > "$HOME/Documents/my notes/.env.example"
printf 'dependency\n' > "$HOME/Documents/my notes/node_modules/dep"
printf 'keep\n' > "$TMP/storage/retained/file"
printf 'remote wrong:destination\nfolder %s\n' "$HOME/Documents/my notes" > "$LAZYMAC_BACKUP_CONF"
fail=0
check() { if eval "$2"; then print "PASS $1"; else print "FAIL $1"; fail=1; fi; }
script() { zsh "$REPO/bin/nogit-backup.sh" "$@" > "$TMP/out" 2>&1; }
daily() { zsh "$REPO/bin/daily.sh" || { cat "$TMP/logs/"*.log; return 1; }; }
script rclone
dest=$TMP/storage/Documents/my\ notes
check "backend local copies to the configured folder with spaces" '[[ -f "$dest/file.txt" ]]'
check "local copy uses the same secret and dependency exclusions" '[[ ! -e "$dest/.env" && ! -e "$dest/node_modules" && -f "$dest/.env.example" ]]'
check "local copy never deletes destination files" '[[ -f "$TMP/storage/retained/file" ]]'
check "local check passes after copying" 'script rclone --check'
ln -s file.txt "$HOME/Documents/my notes/link"
script rclone
check "local check passes after copying a folder that holds a symlink" 'script rclone --check'
printf 'HELLO\n' > "$HOME/Documents/my notes/file.txt"
touch -t 202001010000 "$HOME/Documents/my notes/file.txt"
check "local check detects changed bytes, even at the same size" '! script rclone --check'
script folders
check "local folder list uses the normal manifest" '[[ $(<"$TMP/out") == "Documents/my notes" ]]'
script restore --to "$TMP/restored"
check "local restore copies back from the selected backend" '[[ $(<"$TMP/restored/Documents/my notes/file.txt") == hello ]]'
printf 'kept\n' > "$TMP/restored/Documents/my notes/file.txt"
script restore --to "$TMP/restored"
check "local restore preserves existing files" '[[ $(<"$TMP/restored/Documents/my notes/file.txt") == kept ]]'

# Main Mac sync publishes shared files and its own scan, never another Mac's scan.
export LAZYMAC_HOST=Example-Mac
mkdir -p "$LAZYMAC_DATA/inventory/Example-Mac" "$LAZYMAC_DATA/inventory/Other-Mac"
printf 'own\n' > "$LAZYMAC_DATA/inventory/Example-Mac/marker"
printf 'stale\n' > "$LAZYMAC_DATA/inventory/Other-Mac/marker"
zsh "$REPO/bin/storage.sh" upload
check "main Mac publishes shared data and only its own inventory" \
  '[[ -f "$TMP/storage/catalog.tsv" && -f "$TMP/storage/inventory/Example-Mac/marker" && ! -e "$TMP/storage/inventory/Other-Mac/marker" ]]'
export LAZYMAC_HOST=Other-Mac
printf 'secondary edit\n' > "$LAZYMAC_DATA/catalog.tsv"
zsh "$REPO/bin/storage.sh" upload
check "secondary Mac cannot overwrite shared catalog data" '! grep -q "secondary edit" "$TMP/storage/catalog.tsv"'
check "secondary Mac publishes its own inventory" '[[ -f "$TMP/storage/inventory/Other-Mac/marker" ]]'
zsh "$REPO/bin/storage.sh" download
check "download restores shared files without overwriting own inventory" \
  '! grep -q "secondary edit" "$LAZYMAC_DATA/catalog.tsv" && [[ $(<"$LAZYMAC_DATA/inventory/Other-Mac/marker") == stale ]]'
check "secondary Mac cannot render shared setup files" '! bun "$REPO/bin/catalog.ts" render > "$TMP/out" 2>&1'

# Run the real daily pipeline as a secondary Mac, with only inventory collection stubbed.
seed_inventory "$TMP/scan"
export LAZYMAC_INVENTORY_SCRIPT=$TMP/inventory.sh
printf '#!/bin/zsh\nmkdir -p "$1"\ncp -R "%s/." "$1/"\n' "$TMP/scan" > "$LAZYMAC_INVENTORY_SCRIPT"
daily
check "files off skips folder backup in a successful daily run" \
  'grep -q "=== ok" "$TMP/logs/"*.log && ! grep -q "backup ->" "$TMP/logs/"*.log'
check "daily sync does not use a Git data repository" '[[ ! -d "$LAZYMAC_DATA/.git" && ! -e "$TMP/notified" ]]'
check "storage.conf selects the data folder when the environment is unset" \
  '[[ $(env -u LAZYMAC_DATA zsh "$REPO/bin/storage.sh" path) == "$TMP/data" ]]'
check "LAZYMAC_DATA overrides the configured data folder" \
  '[[ $(LAZYMAC_DATA="$TMP/override" zsh "$REPO/bin/storage.sh" path) == "$TMP/override" ]]'
# A new user (no storage.conf, or one without backend and local lines) backs up to Google Drive with folders off.
check "no storage.conf means Google Drive" '[[ $(LAZYMAC_STORAGE_CONF="$TMP/none.conf" zsh "$REPO/bin/storage.sh" target) == gdrive:LazyMac ]]'
check "no storage.conf keeps folder backup off" '[[ $(LAZYMAC_STORAGE_CONF="$TMP/none.conf" zsh -c "source \"$REPO/bin/storage.sh\"; print \$FILES") == off ]]'
printf 'data %s\n' "$LAZYMAC_DATA" > "$TMP/data-only.conf"
check "storage.conf without backend or local means Google Drive" '[[ $(LAZYMAC_STORAGE_CONF="$TMP/data-only.conf" zsh "$REPO/bin/storage.sh" target) == gdrive:LazyMac ]]'
printf 'remote gdrive:Old\nlocal %s\n' "$TMP/storage" > "$TMP/local-only.conf"
check "storage.conf with a local folder and no backend stays local" '[[ $(LAZYMAC_STORAGE_CONF="$TMP/local-only.conf" zsh "$REPO/bin/storage.sh" target) == "$TMP/storage" ]]'
printf 'backend local\nlocal %s\nfiles on\ndata %s\n' "$TMP/storage" "$LAZYMAC_DATA" > "$LAZYMAC_STORAGE_CONF"
daily
check "files on enables folder copying and comparison in daily" \
  'grep -q "backup ->" "$TMP/logs/"*.log && [[ $(<"$dest/file.txt") == HELLO ]]'

# Exercise the Drive adapter using rclone's real local backend, never Google Drive.
export LAZYMAC_HOST=Example-Mac
printf 'backend gdrive\nremote :local:%s\nfiles off\n' "$TMP/rclone-storage" > "$LAZYMAC_STORAGE_CONF"
zsh "$REPO/bin/storage.sh" upload
LAZYMAC_DATA=$TMP/cloud-restored LAZYMAC_HOST=Fresh-Mac zsh "$REPO/bin/storage.sh" download
check "rclone data copy and restore share the same data layout" \
  'cmp "$LAZYMAC_DATA/catalog.tsv" "$TMP/cloud-restored/catalog.tsv" && [[ -f "$TMP/cloud-restored/inventory/Example-Mac/marker" ]]'
printf 'newer scan\n' > "$LAZYMAC_DATA/inventory/Example-Mac/marker"
zsh "$REPO/bin/storage.sh" download 2> "$TMP/out"
check "rclone download keeps this Mac's own scan" \
  '[[ $(<"$LAZYMAC_DATA/inventory/Example-Mac/marker") == "newer scan" ]] && ! grep -q indeterminate "$TMP/out"'
mkdir -p "$HOME/.bun/bin"
ln -s "$(command -v bun)" "$HOME/.bun/bin/bun"
daily
check "main daily run renders and snapshots without Git synchronization" \
  '[[ -f "$LAZYMAC_DATA/snapshots/$(date +%F).tsv" && -f "$TMP/rclone-storage/snapshots/$(date +%F).tsv" ]]'
exit $fail
