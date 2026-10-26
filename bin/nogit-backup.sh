#!/bin/zsh
# lazymac folder backup: copy folders to a cloud drive with rclone (or the Google Drive app), and bring them back.
# It only copies: it never deletes or changes the source folders, and never deletes anything on the cloud side
# (no --delete). A restore never touches a file that is already there unless you ask it to (--replace).
#
# Skipped: dependencies, build output, caches, scratch (.work), and secret-looking files (.env, keys,
# credentials). Folders inside a target that are their own Git repo with a GitHub remote are skipped too
# (they are already on GitHub). With gitleaks installed, every file it flags is skipped as well.
#
# Settings (the LazyMac app writes them in Back Up > Folders):
#   ~/Library/Application Support/lazymac/backup.conf   (LAZYMAC_BACKUP_CONF=<file> uses another file)
#     remote  <rclone remote:path>   where the copies go, e.g. gdrive:LazyMac/MacBook-Pro
#     folder  <path>                 a folder to back up (~ means the home folder), one line each
#     exclude <pattern>              one more rclone pattern to skip, on top of the built-in ones
#   One "key value" per line; a line starting with # is a note.
# Cloud layout: <remote>/<path under the home folder>, so ~/Documents/notes goes to <remote>/Documents/notes.
# A folder outside the home folder goes to <remote>/_root/<full path>. Each rclone run also writes the folder
# list to <remote>/lazymac-folders.txt, so a restore on a new Mac knows what is there.
# Every rclone, check and restore run adds a line to runs.tsv next to backup.conf:
#   <time UTC>  <backup|check|restore>  <ok|failed>  <remote>
#
# Usage:
#   bin/nogit-backup.sh list                        the folders, their sizes and the repos inside them it skips
#   bin/nogit-backup.sh drive [--dry-run]           copy into the Google Drive for desktop folder
#   bin/nogit-backup.sh rclone [<remote:path>] [--dry-run|--check]
#                                                   copy with rclone, or compare source and copy (same skips)
#   bin/nogit-backup.sh folders [<remote:path>]     the folders a backup holds (from lazymac-folders.txt)
#   bin/nogit-backup.sh restore [<remote:path>] [--to <dir>] [--replace] [<folder>...]
#                                                   copy folders back (all of them, or the ones named as listed by
#                                                   `folders`); --to puts them under <dir> instead of where they
#                                                   were; --replace also replaces files here that are older
set -u
APPBIN=$HOME/Library/Application\ Support/lazymac/bin
export PATH=/opt/homebrew/bin:/usr/local/bin:$APPBIN:/usr/bin:/bin:/usr/sbin:/sbin

CONF=${LAZYMAC_BACKUP_CONF:-$HOME/Library/Application Support/lazymac/backup.conf}
source "${0:A:h}/storage.sh"
RUNS=${CONF:h}/runs.tsv
MANIFEST=lazymac-folders.txt
TARGETS=()
EXTRA=()
CONF_REMOTE=
if [[ -f $CONF ]]; then
  while IFS= read -r line || [[ -n $line ]]; do
    read -r key val <<< "$line"
    [[ -z $key || $key == \#* ]] && continue
    [[ $val == "~" || $val == "~/"* ]] && val=$HOME${val#\~}
    case $key in
      remote) CONF_REMOTE=$val ;;
      folder) TARGETS+=("${val%/}") ;;
      exclude) EXTRA+=("$val") ;;
      *) print -u2 "backup.conf: unknown line: $line" ;;
    esac
  done < "$CONF"
fi
if [[ -f $STORAGE ]]; then CONF_REMOTE=$STORAGE_TARGET
else BACKEND=gdrive  # without storage.conf, the remote line of backup.conf is an rclone remote
fi
[[ -n ${NOGIT_BACKUP_ONLY:-} ]] && TARGETS=(${(M)TARGETS:#*${NOGIT_BACKUP_ONLY}*})
EXCLUDES=(
  node_modules .build build dist DerivedData target .next .turbo .cache __pycache__
  .venv venv .gradle Pods .wrangler .senpi .codegraph .work tmp .DS_Store senpi-task _deps
  .env '.env.*' '*.pem' '*.key' '*.p12' '*.keystore' 'id_rsa*' 'id_ed25519*' '*credentials*.json'
  $EXTRA
)
KEEP=('.env.example')

need_targets() {
  (( ${#TARGETS} )) && return 0
  if [[ -f $CONF ]]; then print -u2 "No folders to back up yet: add some in LazyMac (Back Up > Folders) or as 'folder <path>' lines in $CONF."
  else print -u2 "Folder backup is not set up: open LazyMac (Back Up > Folders), or write $CONF."; fi
  exit 2
}

need_remote() {
  [[ -n $REMOTE ]] && return 0
  print -u2 "No cloud place to copy to: choose where backups go in LazyMac Settings, or add 'remote <name:path>' to $CONF."
  exit 2
}

need_rclone() {
  command -v rclone >/dev/null && return 0
  print -u2 "rclone is not installed: install it with 'brew install rclone' (LazyMac Settings > Backup Place shows how)."
  exit 2
}

# ~/a/b -> a/b; /Volumes/x -> _root/Volumes/x
rel_of() { [[ $1 == $HOME/* ]] && print -r -- "${1#$HOME/}" || print -r -- "_root$1"; }
# the reverse, under $2 (default: the home folder, or / for _root)
place_of() {
  local rel=$1 base=${2:-}
  if [[ -n $base ]]; then print -r -- "$base/$rel"
  elif [[ $rel == _root/* ]]; then print -r -- "${rel#_root}"
  else print -r -- "$HOME/$rel"; fi
}

record() {
  mkdir -p "${RUNS:h}"
  print -r -- "$(date -u +%Y-%m-%dT%H:%M:%SZ)	$1	$2	$REMOTE" >> "$RUNS"
  if (( $(wc -l < "$RUNS") > 500 )); then tail -n 300 "$RUNS" > "$RUNS.new" && mv "$RUNS.new" "$RUNS"; fi
}

capacity_after_backup() {
  [[ $BACKEND == gdrive ]] || return 0
  STORAGE_TARGET=$REMOTE storage_capacity
}

# Sub-folders that are Git repos with a remote (already on GitHub) -> skip.
remote_repos() {
  local t=$1 g
  for g in $t/**/.git(N/) $t/**/.git(N.); do
    local r=${g:h}
    [[ $r == $t ]] && continue
    git -C $r remote get-url origin >/dev/null 2>&1 && print -r -- ${r#$t/}
  done
}

# Files gitleaks flags inside a target -> skip (paths relative to the target). Nothing when gitleaks is missing.
leaked_files() {
  command -v gitleaks >/dev/null || return 0
  local t=$1 rep=$(mktemp)
  gitleaks dir "$t" --max-target-megabytes 5 --no-banner --redact -l error -f json -r "$rep" >/dev/null 2>&1
  jq -r '.[].File' "$rep" 2>/dev/null | sed "s#^$t/##" | sort -u
  rm -f "$rep"
}

filters() {
  local t=$1 e
  f=()
  for e in $KEEP; do f+=(--filter "+ $e"); done
  for e in $EXCLUDES; do f+=(--filter "- $e" --filter "- $e/**"); done
  for e in $(remote_repos $t); do f+=(--filter "- /$e/**"); done
  for e in ${(f)"$(leaked_files $t)"}; do f+=(--filter "- /$e"); print -r -- "   skip (gitleaks): $e"; done
}

case ${1:-list} in
  list)
    need_targets
    for t in $TARGETS; do
      [[ -d $t ]] || { print "missing: $t"; continue; }
      print -r -- "$(du -sh $t | cut -f1)	${t/#$HOME/~}	skip-repos: $(remote_repos $t | tr '\n' ' ')"
    done ;;
  drive)
    need_targets
    root=(~/Library/CloudStorage/GoogleDrive-*/"My Drive"(N/))
    if [[ -n ${NOGIT_BACKUP_DEST:-} ]]; then dest=$NOGIT_BACKUP_DEST
    elif [[ -n $root ]]; then dest="$root[1]/mac-backup/lazymac/$(scutil --get LocalHostName)"
    else print -u2 "Google Drive for desktop is not set up (no ~/Library/CloudStorage/GoogleDrive-*)."; exit 2; fi
    dry=(); [[ ${2:-} == --dry-run ]] && dry=(-n)
    mkdir -p "$dest"
    for t in $TARGETS; do
      [[ -d $t ]] || continue
      rel=$(rel_of $t); mkdir -p "$dest/${rel:h}"
      a=()
      for e in $KEEP; do a+=(--include=$e); done
      for e in $EXCLUDES; do a+=(--exclude=$e); done
      for e in $(remote_repos $t); do a+=(--exclude=/${t:t}/$e); done
      print -r -- "== ${t/#$HOME/~}"
      for e in ${(f)"$(leaked_files $t)"}; do a+=(--exclude=/${t:t}/$e); print -r -- "   skip (gitleaks): $e"; done
      rsync -a $dry --stats $a "$t" "$dest/${rel:h}/"
    done ;;
  rclone)
    shift
    REMOTE=$CONF_REMOTE
    [[ ${1:-} == [^-]* ]] && { REMOTE=$1; shift; }
    op=(copy); kind=backup
    case ${1:-} in --dry-run) op=(copy --dry-run); kind= ;; --check) op=(check --one-way); kind=check ;; esac
    need_targets; need_remote
    if [[ $BACKEND == local ]]; then
      storage_valid || exit $?
      [[ ${REMOTE:A} != ${DATA:A} ]] || exit 2
      for t in $TARGETS; do
        [[ ${REMOTE:A} != ${t:A} && ${REMOTE:A} != ${t:A}/* ]] || {
          print -u2 "The backup destination cannot be inside a source folder."; exit 2
        }
      done
    else
      need_rclone
    fi
    rc=0
    for t in $TARGETS; do
      if [[ ! -d $t ]]; then print -u2 "MISSING: ${t/#$HOME/~} (not backed up)"; rc=1; continue; fi
      print -r -- "== ${t/#$HOME/~}"
      filters $t
      if [[ $BACKEND == local ]]; then
        dest="$REMOTE/$(rel_of $t)"
        if [[ $kind == check ]]; then
          changes=$(rsync -rnc --out-format='%n' "${f[@]}" "$t/" "$dest/") || rc=1
          [[ -z $changes ]] || { print -r -- "$changes"; rc=1; }
        else
          dry=(); [[ -z $kind ]] && dry=(-n)
          if [[ -n $kind ]]; then mkdir -p "$dest" || { rc=1; continue; }; fi
          rsync -a --checksum $dry "${f[@]}" "$t/" "$dest/" || rc=1
        fi
      else
        rclone $op --stats-one-line -P "${f[@]}" "$t" "$REMOTE/$(rel_of $t)" || { rc=1; print -u2 "FAILED: ${t/#$HOME/~}"; }
      fi
    done
    if [[ $kind == backup ]]; then
      if [[ $BACKEND == local ]]; then
        mkdir -p "$REMOTE" && { for t in $TARGETS; do rel_of $t; done > "$REMOTE/$MANIFEST"; } || rc=1
      else
        for t in $TARGETS; do rel_of $t; done | rclone rcat "$REMOTE/$MANIFEST" || { rc=1; print -u2 "FAILED: could not write $MANIFEST"; }
        capacity_after_backup
      fi
    fi
    [[ -n $kind ]] && record $kind $( (( rc == 0 )) && print ok || print failed )
    exit $rc ;;
  folders)
    shift
    REMOTE=${1:-$CONF_REMOTE}
    need_remote
    if [[ $BACKEND == local ]]; then
      cat "$REMOTE/$MANIFEST" 2>/dev/null
    else
      need_rclone
      rclone cat "$REMOTE/$MANIFEST" 2>/dev/null
    fi || { print -u2 "No folder list in $REMOTE (nothing backed up there by LazyMac yet)."; exit 3; } ;;
  restore)
    shift
    REMOTE=$CONF_REMOTE; to=; mode=(--ignore-existing); only=()
    [[ ${1:-} == [^-]* && ${1:-} == *:* ]] && { REMOTE=$1; shift; }
    while (( $# )); do
      case $1 in
        --to) to=${2:?--to needs a folder}; shift 2 ;;
        --replace) mode=(--update); shift ;;
        *) only+=("$1"); shift ;;
      esac
    done
    need_remote
    [[ $BACKEND == local ]] || need_rclone
    if (( ! ${#only} )); then
      if [[ $BACKEND == local ]]; then
        only=(${(f)"$(cat "$REMOTE/$MANIFEST" 2>/dev/null)"})
      else
        only=(${(f)"$(rclone cat "$REMOTE/$MANIFEST" 2>/dev/null)"})
      fi
      (( ${#only} )) || { print -u2 "No folder list in $REMOTE (nothing backed up there by LazyMac yet)."; exit 3; }
    fi
    rc=0
    for rel in $only; do
      [[ $rel != /* && "/$rel/" != *"/../"* ]] || { print -u2 "Invalid folder path: $rel"; rc=1; continue; }
      dest=$(place_of $rel $to)
      print -r -- "== $rel -> ${dest/#$HOME/~}"
      mkdir -p "$dest" || { rc=1; continue; }
      if [[ $BACKEND == local ]]; then
        rsync -a $mode "$REMOTE/$rel/" "$dest/" || rc=1
      else
        rclone copy $mode --stats-one-line -P "$REMOTE/$rel" "$dest" || { rc=1; print -u2 "FAILED: $rel"; }
      fi
    done
    record restore $( (( rc == 0 )) && print ok || print failed )
    exit $rc ;;
  *) print -u2 "usage: $0 list | drive [--dry-run] | rclone [<remote:path>] [--dry-run|--check] | folders [<remote:path>] | restore [<remote:path>] [--to <dir>] [--replace] [<folder>...]"; exit 64 ;;
esac
