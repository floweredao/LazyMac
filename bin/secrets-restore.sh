#!/bin/zsh
# lazymac secrets-restore: decrypt secrets/secrets.tar.age (made by bin/secrets-pack.sh)
# and put every file back at its place under ~ and every Keychain item back into
# the login Keychain. You type the passphrase at age's prompt. Secret values are
# never printed. Files that already exist with different content are first moved to
# ~/.local/share/lazymac/restore-backup-<time>/.
#
# Usage: bin/secrets-restore.sh [--list] [--no-keychain] [bundle]
#   --list          show what is inside (paths and Keychain service names), change nothing
#   --no-keychain   restore files only
# Test hooks: LAZYMAC_KEYCHAIN=<keychain file>
set -euo pipefail
umask 077
export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C

REPO=${0:A:h:h}
source "$REPO/bin/storage.sh"
KC=${LAZYMAC_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}
KCDIR=.lazymac-keychain
list=0 keychain=1 BUNDLE=$DATA/secrets/secrets.tar.age
for arg in "$@"; do
  case $arg in
    --list) list=1 ;;
    --no-keychain) keychain=0 ;;
    -*) print -u2 "usage: ${0:t} [--list] [--no-keychain] [bundle]"; exit 2 ;;
    *) BUNDLE=$arg ;;
  esac
done
command -v age >/dev/null || { print -u2 "age is not installed: brew install age"; exit 1; }
[[ -f $BUNDLE ]] || { print -u2 "bundle not found: $BUNDLE (restore your data from storage first)"; exit 1; }

# 1) Decrypt into a private temp folder (mode 700, outside the repo, deleted on exit)
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/lazymac-restore.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT INT TERM
print "Decrypting ${BUNDLE/#$HOME/~}. age will ask for the passphrase."
if ! age -d "$BUNDLE" | tar -xpf - -C "$STAGE"; then
  print -u2 "decrypt failed (wrong passphrase or damaged file); nothing was changed"; exit 1
fi

cd "$STAGE"
files=( **/*(ND.,ND@) )
files=( ${files:#$KCDIR/*} )
items=()
if [[ -f $KCDIR/items.tsv ]]; then
  while IFS= read -r row; do items+=("$row"); done < "$KCDIR/items.tsv"
fi

if (( list )); then
  print "Files (${#files}):"; for f in "${files[@]}"; do print -r -- "  ~/$f"; done
  print "Keychain items (${#items}):"; for row in "${items[@]}"; do print -r -- "  ${${row#*$'\t'}%%$'\t'*}"; done
  exit 0
fi

# 2) Files: back up differing existing files, copy with original mode, never group/world readable
BACKUP=$HOME/.local/share/lazymac/restore-backup-$(date +%Y%m%d-%H%M%S)
restored=0 backed=0
for f in "${files[@]}"; do
  dest=$HOME/$f
  if [[ -e $dest || -L $dest ]]; then
    cmp -s "$f" "$dest" && { restored=$((restored + 1)); continue; }
    mkdir -p "${BACKUP}/${f:h}" && mv "$dest" "$BACKUP/$f" && backed=$((backed + 1))
  fi
  dir=${dest:h} newdirs=()
  while [[ ! -d $dir ]]; do newdirs+=("$dir"); dir=${dir:h}; done
  mkdir -p "${dest:h}"
  (( ${#newdirs} )) && chmod 700 "${newdirs[@]}"
  cp -pP "$f" "$dest"
  [[ -L $dest ]] || chmod go-rwx "$dest"
  restored=$((restored + 1))
done
[[ -d $HOME/.ssh ]] && chmod 700 "$HOME/.ssh"
print "Files restored: $restored of ${#files}."
(( backed )) && print -r -- "Replaced files were moved to ${BACKUP/#$HOME/~} ($backed)."

# 3) Keychain: add or update each item (-U); the value goes in as hex (-X)
if (( keychain && ${#items} )); then
  ok=0
  for row in "${items[@]}"; do
    i=${row%%$'\t'*} rest=${row#*$'\t'}
    svc=${rest%%$'\t'*} acct=${rest#*$'\t'}
    if security add-generic-password -U -a "$acct" -s "$svc" -X "$(cat -- "$KCDIR/$i.hex")" "$KC" 2>/dev/null; then
      ok=$((ok + 1))
    else
      print -u2 -r -- "warn: could not add Keychain item $svc"
    fi
  done
  print "Keychain items restored: $ok of ${#items}."
fi
