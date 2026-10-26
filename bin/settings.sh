#!/bin/zsh
# lazymac settings: save this Mac's settings into the data folder (dotfiles/), so `setup.sh dotfiles` can put
# them back on a new Mac:
#   - the settings files in DOTFILES (bin/storage.sh): shell, Git, tmux, npm and SSH settings
#   - the current values of the macOS settings listed in dotfiles/macos-defaults.tsv; a new list starts with
#     the Dock and Finder settings below that this Mac has set
# A file gitleaks flags as holding a secret is not saved (list it in secrets/manifest.txt for the encrypted
# bundle instead). Nothing is ever deleted: a file this Mac does not have keeps its saved copy.
#
# Usage: bin/settings.sh save
# Test hook: LAZYMAC_DEFAULTS=<program> answers `read-type` and `read` instead of /usr/bin/defaults.
set -u
umask 077
REPO=${0:A:h:h}
source "$REPO/bin/storage.sh"
[[ ${1:-} == save ]] || { print -u2 "usage: ${0:t} save"; exit 2; }
command -v gitleaks >/dev/null || { print -u2 "gitleaks is not installed; settings were not saved"; exit 1; }
DEFAULTS=${LAZYMAC_DEFAULTS:-/usr/bin/defaults}
OUT=$DATA/dotfiles
TSV=$OUT/macos-defaults.tsv
STARTER=(
  "com.apple.dock autohide" "com.apple.dock tilesize" "com.apple.dock magnification" "com.apple.dock largesize"
  "com.apple.dock orientation" "com.apple.dock show-recents" "com.apple.dock minimize-to-application"
  "com.apple.finder ShowPathbar" "com.apple.finder ShowStatusBar" "com.apple.finder FXPreferredViewStyle"
  "NSGlobalDomain AppleShowAllExtensions"
)
mkdir -p "$OUT" || exit 1

saved=() secret=()
for f in $DOTFILES; do
  src=$HOME/${f/#ssh\//.ssh/}
  [[ -f $src ]] || continue
  gitleaks dir "$src" -c "$REPO/.gitleaks.toml" --no-banner --redact -l error --exit-code 3 >/dev/null 2>&1
  case $? in
    0) mkdir -p "$OUT/${f:h}" && cp "$src" "$OUT/$f.partial" && mv "$OUT/$f.partial" "$OUT/$f" || exit 1
       saved+=$f ;;
    3) secret+=$f
       print -u2 -r -- "not saved, it looks like it holds a secret: ${src/#$HOME/~}" ;;
    *) print -u2 -r -- "gitleaks could not check ${src/#$HOME/~}; settings were not saved"; exit 1 ;;
  esac
done

# current <domain> <key>: "<type>\t<value>" for a bool, int, float or one-line string setting; fails otherwise.
current() {
  local t v
  t=$("$DEFAULTS" read-type "$1" "$2" 2>/dev/null) || return 1
  v=$("$DEFAULTS" read "$1" "$2" 2>/dev/null) || return 1
  [[ $v != *[$'\n\t']* ]] || return 1
  case $t in
    *boolean) [[ $v == 1 ]] && v=true || v=false; print -r -- "bool	$v" ;;
    *integer) print -r -- "int	$v" ;;
    *float) print -r -- "float	$v" ;;
    *string) print -r -- "string	$v" ;;
    *) return 1 ;;
  esac
}

tmp=$(mktemp "$TSV.XXXXXX") || exit 1
n=0
if [[ -f $TSV ]]; then
  while IFS= read -r line || [[ -n $line ]]; do
    IFS=$'\t' read -r domain key kind value rest <<< "$line"
    if [[ -n $domain && $domain != \#* && -n $key ]] && cur=$(current "$domain" "$key"); then
      line="$domain	$key	$cur${rest:+	$rest}"
      n=$((n + 1))
    fi
    print -r -- "$line"
  done < "$TSV" > "$tmp"
else
  print -r -- "# domain	key	type	value (saved by bin/settings.sh, put back by setup.sh dotfiles)" > "$tmp"
  for pair in $STARTER; do
    cur=$(current "${pair%% *}" "${pair#* }") || continue
    print -r -- "${pair%% *}	${pair#* }	$cur" >> "$tmp"
    n=$((n + 1))
  done
fi
mv "$tmp" "$TSV" || exit 1
print -r -- "saved settings: ${#saved} files, $n macOS settings$( (( ${#secret} )) && print -r -- ", ${#secret} left out (secret)")"
