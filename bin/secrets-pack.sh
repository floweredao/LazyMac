#!/bin/zsh
# lazymac secrets-pack: put the secret files and Keychain items named in
# secrets/manifest.txt into ONE age-encrypted file, secrets/secrets.tar.age.
#
# You type the passphrase at age's prompt (twice). This script never sees,
# stores or prints the passphrase, and never prints secret values.
# Plain-text copies of Keychain values exist only in a private temp folder
# (mode 700, outside the repo) for the few seconds of packing, then are deleted.
#
# Usage: bin/secrets-pack.sh             pack and encrypt
#        bin/secrets-pack.sh --dry-run   list what would go in (paths and Keychain service names only)
# Test hooks: LAZYMAC_KEYCHAIN=<keychain file>  LAZYMAC_SECRETS_OUT=<output file>  LAZYMAC_MANIFEST=<file>
set -euo pipefail
umask 077
export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C

REPO=${0:A:h:h}
source "$REPO/bin/storage.sh"
MANIFEST=${LAZYMAC_MANIFEST:-$DATA/secrets/manifest.txt}
OUT=${LAZYMAC_SECRETS_OUT:-$DATA/secrets/secrets.tar.age}
KC=${LAZYMAC_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}
KCDIR=.lazymac-keychain   # top-level folder for Keychain items inside the archive

dry=0
case ${1:-} in
  --dry-run) dry=1 ;;
  '') ;;
  *) print -u2 "usage: ${0:t} [--dry-run]"; exit 2 ;;
esac
command -v age >/dev/null || { print -u2 "age is not installed: brew install age"; exit 1; }
[[ -f $MANIFEST ]] || { print -u2 "manifest not found: $MANIFEST"; exit 1; }

# 1) Read the manifest
typeset -a file_pats excludes kc_pats
while IFS= read -r line || [[ -n $line ]]; do
  [[ -z ${line//[[:space:]]/} || $line == \#* ]] && continue
  case $line in
    exclude:*)  excludes+=("${line#exclude:}") ;;
    keychain:*) kc_pats+=("${line#keychain:}") ;;
    *)          file_pats+=("$line") ;;
  esac
done < "$MANIFEST"

# 2) Files: expand globs relative to ~, keep the ones that exist
typeset -a files missing
cd "$HOME"
for pat in "${file_pats[@]}"; do
  matches=( ${~pat}(N) )
  if (( ${#matches} )); then files+=("${matches[@]}"); else missing+=("$pat"); fi
done

# 3) Keychain: list generic-password items (attributes only, never data) and match services
typeset -a kc_items kc_missing
if [[ -f $KC ]] && (( ${#kc_pats} )); then
  listing=$(security dump-keychain "$KC" 2>/dev/null | awk '
    function flush() { if (cls == "genp" && svc != "") print svc "\t" acct; cls = ""; svc = ""; acct = "" }
    /^keychain: / { flush(); next }
    /^class: /    { cls = $2; gsub(/"/, "", cls); next }
    /^    "svce"<blob>="/ { s = $0; sub(/^    "svce"<blob>="/, "", s); sub(/"$/, "", s); svc = s; next }
    /^    "acct"<blob>="/ { a = $0; sub(/^    "acct"<blob>="/, "", a); sub(/"$/, "", a); acct = a; next }
    END { flush() }' | sort -u)
fi
for pat in "${kc_pats[@]}"; do
  found=0
  for row in "${(@f)listing:-}"; do
    [[ -z $row ]] && continue
    [[ ${row%%$'\t'*} == ${~pat} ]] && { kc_items+=("$row"); found=1; }
  done
  (( found )) || kc_missing+=("$pat")
done
kc_items=( ${(u)kc_items} )

# 4) Report (names only)
print "Files and folders from ~ (${#files}):"
typeset -a exargs
for e in "${excludes[@]}"; do exargs+=(--exclude "$e"); done
for f in "${files[@]}"; do
  if [[ -d $f ]]; then
    n=$(tar -cf - "${exargs[@]}" -- "$f" | tar -tf - | grep -vc '/$' || true)
    print -r -- "  ~/$f/  (folder, $n files)"
  else print -r -- "  ~/$f"; fi
done
(( ${#excludes} )) && print -r -- "Excluded inside folders: ${(j:, :)excludes}"
print "Keychain items (${#kc_items}):"
typeset -A per_svc
for row in "${kc_items[@]}"; do per_svc[${row%%$'\t'*}]=$(( ${per_svc[${row%%$'\t'*}]:-0} + 1 )); done
for svc in ${(ko)per_svc}; do print -r -- "  $svc$( (( per_svc[$svc] > 1 )) && print " (x${per_svc[$svc]})")"; done
(( ${#missing} + ${#kc_missing} )) && {
  print "Not on this Mac, skipped:"
  for m in "${missing[@]}"; do print -r -- "  ~/$m"; done
  for m in "${kc_missing[@]}"; do print -r -- "  keychain:$m"; done
}
if (( dry )); then print "(dry run: nothing read or written)"; exit 0; fi
if [[ ${OUT:A} == ${DATA:A}/* && $STORAGE_ROLE != main ]]; then
  print -u2 "Only the main Mac may update the shared secrets bundle."; exit 2
fi
(( ${#files} + ${#kc_items} )) || { print -u2 "nothing to pack"; exit 1; }

# 5) Export Keychain values as hex into a private temp folder (deleted on exit)
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/lazymac-pack.XXXXXX")
TMPOUT=$OUT.partial
trap 'rm -rf "$STAGE"; rm -f "$TMPOUT"' EXIT INT TERM
mkdir -p "$STAGE/$KCDIR"
i=0
for row in "${kc_items[@]}"; do
  svc=${row%%$'\t'*} acct=${row#*$'\t'}
  i=$((i + 1))
  # -g writes 'password: "text"' or 'password: 0xHEX ...' to stderr; keep it only in $STAGE
  if ! security find-generic-password -s "$svc" -a "$acct" -g "$KC" >/dev/null 2>"$STAGE/raw"; then
    print -u2 "warn: could not read Keychain item $svc (denied or locked), skipped"; continue
  fi
  raw=$(<"$STAGE/raw"; print x); raw=${raw%$'\n'x}
  if [[ $raw == 'password: 0x'* ]]; then
    hex=${${raw#password: 0x}%% *}
  elif [[ $raw == 'password: "'*'"' ]]; then
    val=${${raw#password: \"}%\"}
    hex=$(print -rn -- "$val" | od -An -tx1 | tr -d ' \n')
  elif [[ $raw == 'password: ' || $raw == 'password:' ]]; then
    hex=""
  else
    print -u2 "warn: unexpected Keychain output for $svc, skipped"; continue
  fi
  print -rn -- "$hex" > "$STAGE/$KCDIR/$i.hex"
  print -r -- "$i	$svc	$acct" >> "$STAGE/$KCDIR/items.tsv"
done
rm -f "$STAGE/raw"

# 6) tar | age -p  (age asks for the passphrase on the terminal)
mkdir -p "${OUT:h}"
print "Encrypting. age will ask for a passphrase twice; keep it in your password manager."
tar -cf - "${exargs[@]}" -C "$HOME" -- "${files[@]}" -C "$STAGE" "$KCDIR" | age -p -o "$TMPOUT"
[[ $(head -c 21 "$TMPOUT") == age-encryption.org/v1 ]] || { print -u2 "output is not an age file, aborting"; exit 1; }
mv -f "$TMPOUT" "$OUT"
print -r -- "Wrote ${OUT/#$HOME/~} ($(du -h "$OUT" | cut -f1 | tr -d ' ')): ${#files} paths, $(wc -l < "$STAGE/$KCDIR/items.tsv" 2>/dev/null | tr -d ' ' || print 0) Keychain items."
if [[ ${OUT:A} == ${DATA:A}/* ]]; then storage_data upload; fi
