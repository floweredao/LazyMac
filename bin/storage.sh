#!/bin/zsh
# Shared storage configuration and non-deleting data synchronization. Safe to source.
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/Library/Application Support/lazymac/bin:$PATH"
STORAGE=${LAZYMAC_STORAGE_CONF:-$HOME/Library/Application Support/lazymac/storage.conf}
# Backups go to Google Drive (through rclone) unless storage.conf says "backend local" (a folder, for example
# on an external disk). A storage.conf without a backend line means Google Drive, unless it names a local folder.
BACKEND= STORAGE_REMOTE=gdrive:LazyMac LOCAL= FILES=off DATA=$HOME/LazyMac-data
if [[ -f $STORAGE ]]; then
  while IFS= read -r line || [[ -n $line ]]; do
    read -r key val <<< "$line"
    [[ -z $key || $key == \#* ]] && continue
    [[ $val == "~" || $val == "~/"* ]] && val=$HOME${val#\~}
    case $key in
      backend) BACKEND=$val ;;
      remote) STORAGE_REMOTE=$val ;;
      local) LOCAL=$val ;;
      files) FILES=$val ;;
      data) DATA=$val ;;
    esac
  done < "$STORAGE"
fi
if [[ -z $BACKEND ]]; then
  BACKEND=gdrive
  [[ -n $LOCAL ]] && BACKEND=local
fi
# The settings files bin/settings.sh saves into dotfiles/ and `setup.sh dotfiles` puts back (ssh/ is ~/.ssh/).
DOTFILES=(.zshrc .zshenv .zprofile .gitconfig .tmux.conf .npmrc ssh/config)
DATA=${LAZYMAC_DATA:-$DATA}
export LAZYMAC_DATA=$DATA
STORAGE_TARGET=$STORAGE_REMOTE
[[ $BACKEND == local ]] && STORAGE_TARGET=$LOCAL
STORAGE_HOST=${LAZYMAC_HOST:-$(scutil --get LocalHostName 2>/dev/null || hostname -s)}
STORAGE_ROLE=extra
if [[ -f $DATA/machines.tsv ]]; then
  STORAGE_ROLE=$(awk -F '\t' -v h="$STORAGE_HOST" '$1 == h { r=$2 } END { print (r=="main" ? "main" : "extra") }' "$DATA/machines.tsv")
fi

storage_valid() {
  [[ $BACKEND == gdrive || $BACKEND == local ]] || { print -u2 "Unknown storage backend: $BACKEND"; return 2; }
  [[ -n $STORAGE_TARGET ]] || { print -u2 "Choose a storage destination in LazyMac Settings."; return 2; }
  if [[ $BACKEND == local ]]; then
    [[ $LOCAL == /* ]] || { print -u2 "The local destination must be an absolute folder path."; return 2; }
    # A folder on an external disk that is not plugged in: say so instead of failing to create it.
    if [[ $LOCAL == /Volumes/?* ]]; then
      local vol=/Volumes/${${LOCAL#/Volumes/}%%/*}
      [[ -L $vol ]] || [[ -d $vol && $(stat -f %d "$vol") != $(stat -f %d /Volumes) ]] || {
        print -u2 "The backup disk ${vol:t} is not connected. Connect it and try again."; return 2
      }
    fi
    # A destination inside the source would recursively copy itself.
    local src=${DATA:A} dst=${LOCAL:A}
    [[ $dst != $src && $dst != $src/* && $src != $dst/* ]] || {
      print -u2 "Data and storage folders must not contain each other."; return 2
    }
  fi
}

storage_capacity() {
  [[ $BACKEND == gdrive ]] || return 0
  local cache=${STORAGE:h}/storage-status.json report tmp free total
  mkdir -p "${cache:h}" || return 0
  report=$(mktemp); tmp=$(mktemp "${cache}.XXXXXX") || return 0
  if rclone about --json "$STORAGE_TARGET" > "$report" 2>/dev/null &&
      free=$(plutil -extract free raw -expect integer -o - "$report" 2>/dev/null); then
    plutil -create xml1 "$tmp"
    plutil -replace available -integer "$free" "$tmp"
    total=$(plutil -extract total raw -expect integer -o - "$report" 2>/dev/null) &&
      plutil -replace total -integer "$total" "$tmp"
    plutil -replace stale -bool false "$tmp"
  else
    if [[ $(plutil -extract target raw -o - "$cache" 2>/dev/null) == $STORAGE_TARGET ]]; then
      cp "$cache" "$tmp"
    else
      plutil -create xml1 "$tmp"
    fi
    plutil -replace stale -bool true "$tmp"
  fi
  plutil -replace target -string "$STORAGE_TARGET" "$tmp"
  plutil -replace attemptedAt -integer "$(date +%s)" "$tmp"
  plutil -convert json "$tmp"
  [[ -s $tmp ]] && mv "$tmp" "$cache"
  rm -f "$report" "$tmp"
  return 0
}

storage_data() {
  storage_valid || return $?
  local direction=$1 entry rc=0 src dst
  local -a shared=(catalog.tsv groups.tsv machines.tsv profiles setup snapshots dotfiles secrets)
  mkdir -p "$DATA" || return 1
  if [[ $direction == upload ]]; then
    # A secondary Mac can never publish a stale catalog or another Mac's inventory.
    [[ $STORAGE_ROLE == main ]] || shared=()
    shared+=("inventory/$STORAGE_HOST")
    for entry in $shared; do
      [[ -e $DATA/$entry ]] || continue
      if [[ $BACKEND == local ]]; then
        mkdir -p "$STORAGE_TARGET/${entry:h}" || return 1
        rsync -a --checksum "$DATA/$entry" "$STORAGE_TARGET/${entry:h}/" || rc=1
      elif [[ -d $DATA/$entry ]]; then
        rclone copy "$DATA/$entry" "$STORAGE_TARGET/$entry" || rc=1
      else
        # copyto keeps a top-level file at the root; copy to "<target>/." makes a folder named "." on Drive.
        rclone copyto "$DATA/$entry" "$STORAGE_TARGET/$entry" || rc=1
      fi
    done
    storage_capacity
    mkdir -p "${STORAGE:h}"
    printf '%s\tbackup\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      "$( (( rc == 0 )) && print ok || print failed )" "$STORAGE_TARGET" >> "${STORAGE:h}/storage-runs.tsv"
  else
    # Refresh shared data and the other Macs' scans, never overwrite this Mac's scan.
    if [[ $BACKEND == local ]]; then
      [[ -d $STORAGE_TARGET ]] || { print -u2 "Storage folder not found."; return 1; }
      for entry in $shared inventory; do
        [[ -e $STORAGE_TARGET/$entry ]] || continue
        rsync -a --checksum --exclude="/inventory/$STORAGE_HOST/***" "$STORAGE_TARGET/$entry" "$DATA/" || rc=1
      done
    else
      local -a filters
      for entry in $shared inventory; do filters+=(--include "/$entry" --include "/$entry/**"); done
      rclone copy --exclude "/inventory/$STORAGE_HOST/**" "${filters[@]}" --exclude '*' "$STORAGE_TARGET" "$DATA" || rc=1
    fi
  fi
  return $rc
}

if [[ ${ZSH_EVAL_CONTEXT} == toplevel ]]; then
  case ${1:-} in
    upload|download) storage_data "$1" ;;
    capacity) storage_capacity ;;
    path) print -r -- "$DATA" ;;
    target) storage_valid && print -r -- "$STORAGE_TARGET" ;;
    init)
      # init [example]: the small fictional example list, to try LazyMac. init empty: a new, empty list for
      # this Mac (a real first backup; the example items are not on a real Mac, so they would all be pruned).
      [[ ${2:-example} == (example|empty) ]] || { print -u2 "usage: storage.sh init [example|empty]"; exit 2; }
      [[ ! -e $DATA/catalog.tsv ]] || { print -u2 "Data is already initialized."; exit 2; }
      if [[ -d $DATA && -n $(find "$DATA" -mindepth 1 -maxdepth 1 -print -quit) ]]; then
        print -u2 "Starting a new list requires an empty data folder."; exit 2
      fi
      mkdir -p "$DATA" || exit 1
      if [[ ${2:-example} == empty ]]; then
        head -n 1 "${0:A:h:h}/example/catalog.tsv" > "$DATA/catalog.tsv" || exit 1
        head -n 1 "${0:A:h:h}/example/groups.tsv" > "$DATA/groups.tsv" || exit 1
        printf 'host\trole\tprofiles\n%s\tmain\t\n' "$STORAGE_HOST" > "$DATA/machines.tsv"
      else
        cp -R "${0:A:h:h}/example/." "$DATA/" || exit 1
        printf 'host\trole\tprofiles\n%s\tmain\tpro\n' "$STORAGE_HOST" > "$DATA/machines.tsv"
      fi
      ;;
    *) print -u2 "usage: storage.sh upload|download|init [example|empty]|path|target|capacity"; exit 2 ;;
  esac
fi
