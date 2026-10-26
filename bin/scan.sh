#!/bin/zsh
# Scan only this Mac's inventory, then copy data to the selected storage backend.
# --no-push saves locally; --push-only copies the saved data (legacy flag names).
set -u
export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:$HOME/.bun/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
REPO=${0:A:h:h}
source "$REPO/bin/storage.sh"
die() { print -u2 -r -- "scan: $*"; exit 1; }
if [[ ${1:-} != --push-only ]]; then
  dir=$DATA/inventory/$STORAGE_HOST
  zsh "${LAZYMAC_INVENTORY_SCRIPT:-$REPO/bin/inventory.sh}" "$dir" >/dev/null || die "inventory.sh failed"
  command -v gitleaks >/dev/null || die "gitleaks is not installed; inventory was not uploaded"
  gitleaks dir "$dir" -c "$REPO/.gitleaks.toml" --no-banner --redact -l warn \
    || die "gitleaks found a secret; inventory was not uploaded"
  print -r -- "scanned this Mac into inventory/$STORAGE_HOST"
fi
[[ ${1:-} == --no-push ]] || storage_data upload || die "storage copy failed"
