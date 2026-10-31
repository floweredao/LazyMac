#!/bin/zsh
# A Mac without rclone that backs up to a local folder: the daily backup (scan, list, settings, copy) and the
# restore of the app list into a new data folder must work, through the scripts and through the app. PATH has
# no rclone, and every run is inside a sandbox that refuses to start any program named rclone, so a stray
# rclone call fails the test even on a Mac that has rclone installed. Fake data under .work/ only.
# Usage: tests/local-no-rclone.sh   (builds the app with swift build first)
set -euo pipefail
REPO=${0:A:h:h}
mkdir -p "$REPO/.work"
TMP=$(mktemp -d "$REPO/.work/no-rclone.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
source "$REPO/tests/fixtures.zsh"
command -v sandbox-exec >/dev/null || { print "FAIL    sandbox-exec is missing, so rclone cannot be blocked"; exit 1; }
# Named here, not at the assignment further down: under set -e an assignment takes the status of its
# last command substitution, so a missing tool would end the script before any check printed.
for t in bun gitleaks; do
  command -v $t >/dev/null || { print "FAIL    $t is missing, so this test cannot run"; exit 1; }
done
cd "$REPO/app"
swift build -q
BIN=$(swift build --show-bin-path)/lazymac
cd "$REPO"
fail=0
check() { if eval "$2"; then print "ok      $1"; else print "FAIL    $1"; fail=1; fi; }
NORCLONE='(version 1)(allow default)(deny process-exec (regex #"/rclone$"))'
nr() { sandbox-exec -p "$NORCLONE" "$@"; }

BUN=$(command -v bun) GITLEAKS=$(command -v gitleaks)
mkdir -p "$TMP/fake"
print -r -- '#!/bin/sh
exit 0' > "$TMP/fake/rclone"
chmod +x "$TMP/fake/rclone"
check "the sandbox refuses to start rclone, wherever it is" '! nr "$TMP/fake/rclone" 2>/dev/null'
check "the sandbox still starts other programs" 'nr /usr/bin/true'

seed_data
export HOME=$TMP/home PATH=/usr/bin:/bin:/usr/sbin:/sbin RCLONE_CONFIG=$TMP/rclone.conf
export LAZYMAC_DAILY_LOGDIR=$TMP/logs LAZYMAC_DAILY_NOTIFY_FILE=$TMP/notified LAZYMAC_HOOKS=$TMP/hooks
mkdir -p "$HOME/.bun/bin" "$HOME/.local/bin" "$HOME/.ssh"
ln -s "$BUN" "$HOME/.bun/bin/bun"
ln -s "$GITLEAKS" "$HOME/.local/bin/gitleaks"
printf 'export EDITOR=nano\n' > "$HOME/.zshrc"
printf '[user]\n\tname = Example User\n' > "$HOME/.gitconfig"
printf 'Host example\n  HostName example.com\n' > "$HOME/.ssh/config"
# A made-up npm token, made here so that no token-shaped text is ever committed.
printf '//registry.npmjs.org/:_authToken=npm_%s\n' "$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 36)" > "$HOME/.npmrc"
seed_inventory "$TMP/scan"
export LAZYMAC_INVENTORY_SCRIPT=$TMP/inventory.sh
printf '#!/bin/zsh\nmkdir -p "$1"\ncp -R "%s/." "$1/"\n' "$TMP/scan" > "$LAZYMAC_INVENTORY_SCRIPT"

printf 'local %s\nfiles off\ndata %s\n' "$TMP/storage" "$LAZYMAC_DATA" > "$LAZYMAC_STORAGE_CONF"
check "without a backend line, backups go to the local folder" '[[ $(nr zsh "$REPO/bin/storage.sh" target) == "$TMP/storage" ]]'
set +e; nr zsh "$REPO/bin/daily.sh"; code=$?; set -e
check "the daily backup finishes without rclone" '[[ $code == 0 ]] && grep -q "=== ok" "$TMP/logs/"*.log && [[ ! -e $TMP/notified ]]'
check "nothing in the run mentions rclone" '! grep -qi rclone "$TMP/logs/"*.log'
check "it logs each step, in order, for the app" \
  '[[ $(awk "\$3 == \"step\" {printf \"%s \", \$4}" "$TMP/logs/"*.log) == "refresh scan list settings copy " ]]'
check "it copies the app list, the setup lists and this Mac's scan to the folder" \
  '[[ -f $TMP/storage/catalog.tsv && -f $TMP/storage/setup/Brewfile && -f $TMP/storage/inventory/Example-Mac/apps.tsv ]]'
check "it copies the settings files and the macOS settings" \
  '[[ -f $TMP/storage/dotfiles/.zshrc && -f $TMP/storage/dotfiles/.gitconfig && -f $TMP/storage/dotfiles/ssh/config ]] && [[ $(grep -vc "^#" $TMP/storage/dotfiles/macos-defaults.tsv) == 3 ]]'
check "a settings file that holds a secret is left out" '[[ ! -e $TMP/data/dotfiles/.npmrc && ! -e $TMP/storage/dotfiles/.npmrc ]]'

LAZYMAC_DATA=$TMP/restored LAZYMAC_HOST=Fresh-Mac nr zsh "$REPO/bin/storage.sh" download
check "a new Mac gets the app list, setup lists and settings back from the folder" \
  'cmp "$TMP/data/catalog.tsv" "$TMP/restored/catalog.tsv" && cmp "$TMP/data/setup/Brewfile" "$TMP/restored/setup/Brewfile" && [[ -f $TMP/restored/dotfiles/.zshrc && -f $TMP/restored/inventory/Example-Mac/apps.tsv ]]'
LAZYMAC_DATA=$TMP/restored-app LAZYMAC_HOST=Fresh-Mac nr "$BIN" --storage-init restore > "$TMP/out"
check "the app restores the list into an empty data folder" 'cmp "$TMP/data/catalog.tsv" "$TMP/restored-app/catalog.tsv"'
nr "$BIN" --storage-status > "$TMP/status"
check "the app's status card reads the folder's free space" 'jq -e ".available > 0 and .total >= .available and .stale == false" "$TMP/status" >/dev/null'

# A brand-new Mac: the app starts an empty list (no example items to prune) and the first backup works.
export LAZYMAC_DATA=$TMP/new-data LAZYMAC_HOST=New-Mac
printf 'local %s\nfiles off\ndata %s\n' "$TMP/new-storage" "$LAZYMAC_DATA" > "$LAZYMAC_STORAGE_CONF"
nr "$BIN" --storage-init new > "$TMP/out"
check "the app starts a new, empty list with this Mac as the main Mac" \
  '[[ $(grep -c . "$LAZYMAC_DATA/catalog.tsv") == 1 ]] && grep -q "^New-Mac	main" "$LAZYMAC_DATA/machines.tsv" && [[ -f $TMP/new-storage/catalog.tsv ]]'
rm -f "$TMP/logs/"*.log
set +e; nr zsh "$REPO/bin/daily.sh"; code=$?; set -e
check "the first backup of a new list succeeds" '[[ $code == 0 && -f $TMP/new-storage/inventory/New-Mac/apps.tsv ]]'

printf 'local /Volumes/LazyMac-Test-Missing-%s/Backups\nfiles off\ndata %s\n' $$ "$LAZYMAC_DATA" > "$LAZYMAC_STORAGE_CONF"
rm -f "$TMP/logs/"*.log "$TMP/notified"
set +e; nr zsh "$REPO/bin/daily.sh"; code=$?; set -e
check "an unplugged backup disk stops the backup and says so" \
  "[[ \$code == 1 ]] && grep -q 'FAIL: The backup disk LazyMac-Test-Missing-$$ is not connected' \"\$TMP/logs/\"*.log"

printf 'remote gdrive:Old\n' > "$TMP/old.conf"
check "an older storage.conf that names only a remote still means Google Drive" \
  '[[ $(LAZYMAC_STORAGE_CONF=$TMP/old.conf zsh "$REPO/bin/storage.sh" target) == gdrive:Old ]]'
check "without storage.conf, a new Mac backs up to Google Drive" \
  '[[ $(LAZYMAC_STORAGE_CONF=$TMP/none.conf zsh "$REPO/bin/storage.sh" target) == gdrive:LazyMac ]]'
exit $fail
