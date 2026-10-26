#!/bin/zsh
# lazymac setup: put everything marked "keep" in catalog.tsv onto this (new) Mac.
# It reads only the generated lists in setup/ (made by `bun bin/catalog.ts render`).
# Safe to run again: finished parts are skipped. Nothing is ever deleted.
#
# Usage: bin/setup.sh            run every step in order
#        bin/setup.sh <step>...  run only these steps
#        bin/setup.sh --profile <base[,add-on...]> [step...]
#                                install only what the profile picks (profiles/<name>.txt, written out by
#                                `bun bin/catalog.ts profile` into .work/profile-<names>/); without steps it runs
#                                every step except the ones the profile skips
#        bin/setup.sh --list     show the steps
#        bin/setup.sh --release-asset <owner/repo> [pattern]
#                                print the latest release tag and the file this Mac would install
# LAZYMAC_SETUP_DIR=<dir> reads the lists from <dir> instead of setup/ (the lazymac app writes
# the items you picked there, in the same format).
set -u
REPO=${0:A:h:h}
source "$REPO/bin/storage.sh"
S=${LAZYMAC_SETUP_DIR:-$DATA/setup}
export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:$HOME/.bun/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOMEBREW_NO_ENV_HINTS=1
if [[ ${1:-} == --profile ]]; then
  [[ -n ${2:-} ]] || { print -u2 "usage: setup.sh --profile <base[,add-on...]> [step...]"; exit 2; }
  command -v bun >/dev/null || { print -u2 "--profile needs bun (curl -fsSL https://bun.sh/install | bash)"; exit 2; }
  S=$REPO/.work/profile-${2//,/-}
  bun "$REPO/bin/catalog.ts" profile "$2" "$S" || exit 2
  shift 2
fi
source "$S/versions.env"
BACKUP=$HOME/.local/share/lazymac/restore-backup-$(date +%Y%m%d-%H%M%S)

STEPS=(brew node bun python scripts releases dotfiles secrets repos jobs downloads check)
typeset -A ABOUT=(
  brew      "Homebrew, App Store apps and fonts from setup/Brewfile"
  node      "Node.js $NODE_VERSION with nvm, fixed links in ~/.local/bin, npm tools"
  bun       "bun and its global tools"
  python    "Python $PYTHON_VERSION with uv"
  scripts   "tools that ship their own install script (Claude Code, CuaDriver)"
  releases  "apps from the latest GitHub release of their repo (.dmg or .zip)"
  dotfiles  "shell, git, tmux, npm and ssh settings from dotfiles/, and the Dock settings in dotfiles/macos-defaults.tsv"
  secrets   "sign-ins, API keys, private job files and scripts from the encrypted bundle (asks the passphrase)"
  repos     "my-skills and devin-vm"
  jobs      "register the background jobs marked keep (only when their program is in place)"
  downloads "open the download page of each app that has no Homebrew package"
  check     "list what is still missing"
)

lines() { grep -v '^#' "$1" | grep -v '^[[:space:]]*$'; }
say() { print -r -- "$*"; }

step_brew() {
  command -v brew >/dev/null || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  say "App Store apps need you to be signed in to the App Store."
  brew bundle --file="$S/Brewfile"
}

step_node() {
  export NVM_DIR=$HOME/.nvm
  mkdir -p "$NVM_DIR" "$HOME/.local/bin"
  set +u
  source "$(brew --prefix nvm)/nvm.sh" || return 1
  nvm install "$NODE_VERSION" && nvm alias default "$NODE_VERSION" || return 1
  set -u
  local bin=$NVM_DIR/versions/node/v$NODE_VERSION/bin c
  export PATH=$bin:$PATH
  for c in node npm npx; do ln -sfn "$bin/$c" "$HOME/.local/bin/$c"; done
  local pkgs=( ${(f)"$(lines "$S/npm.txt")"} )
  (( ${#pkgs} )) && "$bin/npm" install -g "${pkgs[@]}"
}

step_bun() {
  [[ -x $HOME/.bun/bin/bun ]] || curl -fsSL https://bun.sh/install | bash
  local pkgs=( ${(f)"$(lines "$S/bun.txt")"} )
  (( ${#pkgs} )) && "$HOME/.bun/bin/bun" add -g "${pkgs[@]}"
}

step_python() {
  uv python install "$PYTHON_VERSION"
}

step_scripts() {
  local id url rc=0
  while IFS=$'\t' read -r id url; do
    if command -v "$id" >/dev/null || [[ -d /Applications/$id.app ]]; then say "ok      $id"; continue; fi
    say "install $id ($url)"
    curl -fsSL "$url" | bash || rc=1
  done < <(lines "$S/scripts.tsv")
  return $rc
}

# Pick the file of the latest release this Mac should install: the one matching the pattern if
# given, else a .dmg or .zip for this CPU (arm64 builds first on Apple Silicon), never blockmaps.
release_asset() {
  local repo=$1 pattern=${2:--} out tag n
  local -a names picks
  out=$(gh release view -R "$repo" --json tagName,assets --jq '.tagName, .assets[].name') || return 1
  names=( ${(f)out} )
  tag=${names[1]}
  names=( ${names[2,-1]} )
  if [[ $pattern != - ]]; then
    picks=( ${(M)names:#${~pattern}} )
  else
    names=( ${(M)names:#*.(dmg|zip)} )
    if [[ $(uname -m) == arm64 ]]; then
      names=( ${names:#*(x86_64|x64|intel|Intel|amd64)*} )
      picks=( ${(M)names:#*arm64*.dmg} ${(M)names:#*arm64*.zip} ${(M)names:#*.dmg} ${(M)names:#*.zip} )
    else
      names=( ${names:#*(arm64|aarch64)*} )
      picks=( ${(M)names:#*.dmg} ${(M)names:#*.zip} )
    fi
  fi
  (( ${#picks} )) || { print -u2 "no macOS .dmg or .zip in the latest release of $repo ($tag)"; return 1; }
  print -r -- "$tag	${picks[1]}"
}

# Copy the .app inside a downloaded .dmg or .zip to dest (a full path ending in .app).
install_app() {
  local file=$1 work=$2 dest=$3 rc
  local -a apps
  case $file in
    *.dmg)
      hdiutil attach -nobrowse -readonly -quiet -mountpoint "$work/mnt" "$file" || return 1
      apps=( "$work"/mnt/*.app(N) )
      rc=1
      (( ${#apps} )) && ditto "${apps[1]}" "$dest" && rc=0
      hdiutil detach -quiet "$work/mnt"
      return $rc ;;
    *.zip)
      ditto -x -k "$file" "$work/unzip" || return 1
      apps=( "$work"/unzip/*.app(N) "$work"/unzip/*/*.app(N) )
      (( ${#apps} )) && ditto "${apps[1]}" "$dest" ;;
    *) return 1 ;;
  esac
}

step_releases() {
  local name repo pattern check pick tag asset work rc=0
  local -a hits
  while IFS=$'\t' read -r name repo pattern check; do
    check=${check/#\~/$HOME}
    hits=( ${~check}(N) )
    if (( ${#hits} )); then say "ok      $name"; continue; fi
    pick=$(release_asset "$repo" "$pattern") || { say "failed  $name: no download found in $repo"; rc=1; continue; }
    tag=${pick%%$'\t'*} asset=${pick#*$'\t'}
    say "install $name $tag ($asset)"
    work=$(mktemp -d "${TMPDIR:-/tmp}/lazymac-release.XXXXXX")
    if gh release download "$tag" -R "$repo" -p "$asset" -D "$work" && mkdir -p "${check:h}" \
        && install_app "$work/$asset" "$work" "$check"; then
      say "ok      $name"
    else
      say "failed  $name"; rc=1
    fi
    rm -rf "$work"
  done < <(lines "$S/releases.tsv")
  return $rc
}

step_dotfiles() {
  local f src dest
  for f in .zshrc .zshenv .zprofile .gitconfig .tmux.conf .npmrc ssh/config; do
    src=$DATA/dotfiles/$f
    dest=$HOME/${f/#ssh\//.ssh/}
    [[ -f $src ]] || continue
    mkdir -p "${dest:h}"
    if [[ -f $dest ]] && ! sed -E "s#/Users/[^/\"' ]+#$HOME#g" "$src" | cmp -s - "$dest"; then
      mkdir -p "$BACKUP" && mv "$dest" "$BACKUP/${f:t}" && say "kept old ${dest/#$HOME/~} in ${BACKUP/#$HOME/~}"
    fi
    sed -E "s#/Users/[^/\"' ]+#$HOME#g" "$src" > "$dest.lazymac" && mv "$dest.lazymac" "$dest"
    say "ok      ${dest/#$HOME/~}"
  done
  chmod 700 "$HOME/.ssh" 2>/dev/null; chmod 600 "$HOME/.ssh/config" 2>/dev/null
  local domain key type value rest bad=0 domains=()
  while IFS=$'\t' read -r domain key type value rest; do
    [[ -z $domain || $domain == \#* ]] && continue
    if defaults write "$domain" "$key" "-$type" "$value"; then say "ok      $domain $key = $value"
    else say "failed  $domain $key"; bad=1; fi
    (( ${domains[(Ie)$domain]} )) || domains+=$domain
  done < "$DATA/dotfiles/macos-defaults.tsv"
  (( ${domains[(Ie)com.apple.dock]} )) && killall Dock 2>/dev/null
  return $bad
}

step_secrets() {
  "$REPO/bin/secrets-restore.sh" || return 1
  [[ -z $("$HOME/.bun/bin/bun" "$REPO/bin/omo-anthropic.ts" list 2>/dev/null) ]] || "$HOME/.bun/bin/bun" "$REPO/bin/omo-anthropic.ts" sync
}

step_repos() {
  local rc=0
  if [[ ! -d $HOME/.local/share/my-skills/.git ]]; then
    gh repo clone floweredao/my-skills "$HOME/.local/share/my-skills" || rc=1
  fi
  [[ -d $HOME/.local/share/my-skills ]] && { bash "$HOME/.local/share/my-skills/scripts/install.sh" all || rc=1; }
  if [[ ! -d $HOME/Documents/omo/devin-vm/.git ]]; then
    mkdir -p "$HOME/Documents/omo" && gh repo clone floweredao/devin-vm "$HOME/Documents/omo/devin-vm" || rc=1
  fi
  [[ -d $HOME/Documents/omo/devin-vm ]] && { "$HOME/Documents/omo/devin-vm/install.sh" || say "devin-vm: see the MISSING lines above"; }
  return $rc
}

job_program() {
  local p=$1 a0 a1
  a0=$(/usr/libexec/PlistBuddy -c "Print :Program" "$p" 2>/dev/null || /usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "$p" 2>/dev/null)
  a1=$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:1" "$p" 2>/dev/null)
  [[ -n $a0 && ! -e $a0 ]] && { print -r -- "$a0"; return; }
  [[ $a1 == /* && ! -e $a1 ]] && { print -r -- "$a1"; return; }
  local wd=$(/usr/libexec/PlistBuddy -c "Print :WorkingDirectory" "$p" 2>/dev/null)
  [[ -n $wd && ! -d $wd ]] && print -r -- "$wd"
}

step_jobs() {
  local label p missing on=0 added=0 waiting=0 dom=gui/$(id -u)
  while read -r label; do
    p=$HOME/Library/LaunchAgents/$label.plist
    if launchctl print "$dom/$label" >/dev/null 2>&1; then say "on      $label"; on=$((on + 1)); continue; fi
    # The daily job runs every day only on the main Mac (machines.tsv); another Mac turns it on in the app.
    if [[ $label == local.lazymac-daily && $(bun "$REPO/bin/catalog.ts" machine 2>/dev/null | cut -f1) != main ]]; then
      say "skip    $label: only the main Mac in machines.tsv runs it; turn on Auto Backup in the LazyMac app instead"; continue
    fi
    [[ ! -f $p && -f $REPO/launchd/$label.plist ]] && cp "$REPO/launchd/$label.plist" "$p"
    if [[ ! -f $p ]]; then say "wait    $label: no plist yet (run the secrets step)"; waiting=$((waiting + 1)); continue; fi
    missing=$(job_program "$p")
    if [[ -n $missing ]]; then say "wait    $label: needs ${missing/#$HOME/~}"; waiting=$((waiting + 1)); continue; fi
    plutil -lint -s "$p" && launchctl bootstrap "$dom" "$p" && { say "started $label"; added=$((added + 1)); } \
      || say "failed  $label (see: launchctl print $dom/$label)"
  done < <(lines "$S/jobs.txt")
  say "jobs: $on already on, $added started, $waiting waiting. Run this step again after the waiting parts are in place."
}

step_downloads() {
  local name url check n=0 hits
  while IFS=$'\t' read -r name url check; do
    check=${check/#\~/$HOME}
    hits=( ${~check}(N) )
    if (( ${#hits} )); then say "ok      $name"; continue; fi
    say "open    $name: $url"; open "$url"; n=$((n + 1))
  done < <(lines "$S/downloads.tsv")
  say "$n download pages opened."
}

step_check() {
  local out=$REPO/.work/after-setup
  "$REPO/bin/inventory.sh" "$out" >/dev/null && "$HOME/.bun/bin/bun" "$REPO/bin/catalog.ts" check "$out"
  return 0
}

if [[ ${1:-} == --release-asset ]]; then
  release_asset "${2:?usage: setup.sh --release-asset <owner/repo> [pattern]}" "${3:--}"; exit
fi
if [[ ${1:-} == --list ]]; then
  for s in $STEPS; do printf '%-10s %s\n' $s "$ABOUT[$s]"; done; exit 0
fi
skipped=()
[[ -f $S/skip.txt ]] && skipped=( ${(f)"$(lines "$S/skip.txt")"} )
run=( ${@:-${STEPS:|skipped}} )
for s in $run; do (( ${STEPS[(Ie)$s]} )) || { print -u2 "unknown step: $s (see --list)"; exit 2; }; done
failed=()
for s in $run; do
  say ""; say "== $s: $ABOUT[$s]"
  step_$s || failed+=$s
done
say ""
# Apps LazyMac never installs (catalog how=byhand): always say so, whatever steps ran.
if [[ -f $S/byhand.tsv ]] && [[ -n $(lines "$S/byhand.tsv") ]]; then
  say "Install these apps yourself (LazyMac does not install them):"
  while IFS=$'\t' read -r name ref; do
    [[ $ref == - ]] && say "  - $name" || say "  - $name: $ref"
  done < <(lines "$S/byhand.tsv")
  say ""
fi
if (( ${#failed} )); then say "Finished with problems in: ${failed[*]}. Fix them and run: bin/setup.sh ${failed[*]}"; exit 1; fi
say "Done. Last by hand: App Store sign-in, privacy permissions, app sign-ins, then the restore guides of tools that have their own."
