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
#        bin/setup.sh --dry-run [step...]
#                                show what each step would install or change, without doing it
#        bin/setup.sh --release-asset <owner/repo> [pattern]
#                                print the latest release tag and the file this Mac would install
# Without a GitHub sign-in (a new Mac), public repos and releases come through the public GitHub API.
# LAZYMAC_SETUP_DIR=<dir> reads the lists from <dir> instead of setup/ (the lazymac app writes
# the items you picked there, in the same format).
set -u
REPO=${0:A:h:h}
source "$REPO/bin/storage.sh"
S=${LAZYMAC_SETUP_DIR:-$DATA/setup}
export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:$HOME/.bun/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOMEBREW_NO_ENV_HINTS=1
# Scratch files go next to the code, or to the cache folder when the code is inside LazyMac.app.
WORK=$REPO/.work
[[ $REPO == *.app/Contents/* ]] && WORK=$HOME/Library/Caches/lazymac
DRY=0
[[ ${1:-} == --dry-run ]] && { DRY=1; shift; }
if [[ ${1:-} == --profile ]]; then
  [[ -n ${2:-} ]] || { print -u2 "usage: setup.sh --profile <base[,add-on...]> [step...]"; exit 2; }
  command -v bun >/dev/null || { print -u2 "--profile needs bun (curl -fsSL https://bun.sh/install | bash)"; exit 2; }
  S=$WORK/profile-${2//,/-}
  bun "$REPO/bin/catalog.ts" profile "$2" "$S" || exit 2
  shift 2
fi
source "$S/versions.env"
BACKUP=$HOME/.local/share/lazymac/restore-backup-$(date +%Y%m%d-%H%M%S)
HOOKS=${LAZYMAC_HOOKS:-$HOME/.config/lazymac/hooks}

STEPS=(brew node bun python scripts releases dotfiles secrets repos jobs downloads check)
typeset -A ABOUT=(
  brew      "Homebrew, App Store apps and fonts from setup/Brewfile"
  node      "Node.js $NODE_VERSION with nvm, fixed links in ~/.local/bin, npm tools"
  bun       "bun and its global tools"
  python    "Python $PYTHON_VERSION with uv"
  scripts   "tools that ship their own install script (setup/scripts.tsv)"
  releases  "apps from the latest GitHub release of their repo (.dmg or .zip)"
  dotfiles  "shell, git, tmux, npm and ssh settings from dotfiles/, and the Dock settings in dotfiles/macos-defaults.tsv"
  secrets   "sign-ins, API keys, private job files and scripts from the encrypted bundle (asks the passphrase)"
  repos     "the other projects (Git repos) in setup/repos.tsv, cloned and set up"
  jobs      "register the background jobs marked keep (only when their program is in place)"
  downloads "open the download page of each app that has no Homebrew package"
  check     "list what is still missing"
)

lines() { [[ -f $1 ]] || return 0; grep -v '^#' "$1" | grep -v '^[[:space:]]*$'; }
# gh works only after "gh auth login"; until then (a new Mac) public repos are read without it.
gh_ok() { command -v gh >/dev/null && gh auth status >/dev/null 2>&1; }
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
  if gh_ok; then
    out=$(gh release view -R "$repo" --json tagName,assets --jq '.tagName, .assets[].name') || return 1
  else
    out=$(curl -fsSL -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/$repo/releases/latest" \
      | /usr/bin/jq -r '.tag_name, .assets[].name') && [[ -n $out ]] \
      || { print -u2 "could not read the latest release of $repo (a private repo needs: gh auth login)"; return 1; }
  fi
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

download_asset() {
  local repo=$1 tag=$2 asset=$3 dir=$4
  if gh_ok; then gh release download "$tag" -R "$repo" -p "$asset" -D "$dir"
  else curl -fsSL -o "$dir/$asset" "https://github.com/$repo/releases/download/$tag/$asset"; fi
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
    if download_asset "$repo" "$tag" "$asset" "$work" && mkdir -p "${check:h}" \
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
  for f in $DOTFILES; do
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
  # A doubled tab in IFS is not whitespace to zsh, so an empty value is not replaced by the note after it.
  while IFS=$'\t\t' read -r domain key type value rest; do
    [[ -z $domain || $domain == \#* ]] && continue
    if defaults write "$domain" "$key" "-$type" "$value"; then say "ok      $domain $key = $value"
    else say "failed  $domain $key"; bad=1; fi
    (( ${domains[(Ie)$domain]} )) || domains+=$domain
  done < "$DATA/dotfiles/macos-defaults.tsv"
  (( ${domains[(Ie)com.apple.dock]} )) && killall Dock 2>/dev/null
  return $bad
}

# Once the bundle is back: the omo provider sync, but only on a Mac that keeps those Keychain keys (and it never
# fails this step), then an executable hooks/after-secrets for steps of your own.
step_secrets() {
  "$REPO/bin/secrets-restore.sh" || return 1
  local bun=$HOME/.bun/bin/bun provider=$REPO/bin/omo-anthropic.ts
  if [[ -x $bun && -f $provider ]] && [[ -n $("$bun" "$provider" list 2>/dev/null) ]]; then
    "$bun" "$provider" sync || say "warn    the omo provider sync failed; nothing else was changed"
  fi
  [[ -x $HOOKS/after-secrets ]] || return 0
  say "run     ${HOOKS/#$HOME/~}/after-secrets"
  "$HOOKS/after-secrets" || { say "failed  after-secrets hook failed"; return 1; }
}

# setup/repos.tsv: <owner/repo> <folder> <command run inside it after cloning, or ->, from catalog rows how=repo.
step_repos() {
  local repo folder command rc=0 n=0
  while IFS=$'\t' read -r repo folder command; do
    n=$((n + 1))
    folder=${folder/#\~/$HOME}
    if [[ -d $folder/.git ]]; then
      say "ok      $repo (${folder/#$HOME/~})"
    else
      say "get     $repo -> ${folder/#$HOME/~}"
      mkdir -p "${folder:h}" || { rc=1; continue; }
      if gh_ok; then gh repo clone "$repo" "$folder" || { say "failed  $repo"; rc=1; continue; }
      else
        GIT_TERMINAL_PROMPT=0 git clone -q "https://github.com/$repo.git" "$folder" \
          || { say "failed  $repo: a private repo needs a GitHub sign-in first (gh auth login), then run: bin/setup.sh repos"; rc=1; continue; }
      fi
    fi
    [[ $command == - || -z $command ]] && continue
    if (cd "$folder" && /bin/zsh -c "$command"); then say "ok      $repo: $command"
    else say "failed  $repo: $command"; rc=1; fi
  done < <(lines "$S/repos.tsv")
  (( n )) || say "no other projects in the list"
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
  local label p missing app on=0 added=0 waiting=0 dom=gui/$(id -u)
  while read -r label; do
    p=$HOME/Library/LaunchAgents/$label.plist
    if launchctl print "$dom/$label" >/dev/null 2>&1; then say "on      $label"; on=$((on + 1)); continue; fi
    # The daily job runs every day only on the main Mac (machines.tsv); another Mac turns it on in the app.
    if [[ $label == local.lazymac-daily && $(bun "$REPO/bin/catalog.ts" machine 2>/dev/null | cut -f1) != main ]]; then
      say "skip    $label: only the main Mac in machines.tsv runs it; turn on Auto Backup in the LazyMac app instead"; continue
    fi
    # The app writes the daily job for this Mac (its paths, catch-up after sleep); the launchd/ copy is only a sample.
    if [[ $label == local.lazymac-daily && ! -f $p ]]; then
      app=${REPO:h}/MacOS/lazymac
      [[ -x $app ]] || app=/Applications/LazyMac.app/Contents/MacOS/lazymac
      if [[ -x $app ]] && "$app" --schedule daily:04:00 >/dev/null; then say "started $label (every day at 04:00)"; added=$((added + 1))
      else say "wait    $label: turn on Auto Backup in the LazyMac app"; waiting=$((waiting + 1)); fi
      continue
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
  local out=$WORK/after-setup
  "$REPO/bin/inventory.sh" "$out" >/dev/null && "$HOME/.bun/bin/bun" "$REPO/bin/catalog.ts" check "$out"
  return 0
}

# --dry-run: what each step would do, read from the same lists; it installs, copies and registers nothing.
have() { local -a hits; hits=( ${~1}(N) ); (( ${#hits} )); }
preview_brew() {
  command -v brew >/dev/null && say "Homebrew is installed" || say "would install Homebrew"
  local kind n
  for kind in tap brew cask mas uv; do
    n=$(grep -c "^$kind " "$S/Brewfile" 2>/dev/null)
    (( n )) && say "would add $n $kind: $(grep "^$kind " "$S/Brewfile" | sed -E 's/^[a-z]+ "([^"]+)".*/\1/' | tr '\n' ' ')"
  done
  return 0
}
preview_node() { say "would install Node.js $NODE_VERSION; npm tools: $(lines "$S/npm.txt" | tr '\n' ' ')"; }
preview_bun() { say "bun tools: $(lines "$S/bun.txt" | tr '\n' ' ')"; }
preview_python() { say "would install Python $PYTHON_VERSION with uv"; }
preview_scripts() {
  local id url
  while IFS=$'\t' read -r id url; do
    if command -v "$id" >/dev/null || [[ -d /Applications/$id.app ]]; then say "ok      $id"; else say "would run $url ($id)"; fi
  done < <(lines "$S/scripts.tsv")
}
preview_releases() {
  local name repo pattern check pick rc=0
  while IFS=$'\t' read -r name repo pattern check; do
    check=${check/#\~/$HOME}
    if have "$check"; then say "ok      $name"; continue; fi
    if pick=$(release_asset "$repo" "$pattern"); then say "would install $name ${pick%%$'\t'*} (${pick#*$'\t'})"
    else say "failed  $name: no download found in $repo"; rc=1; fi
  done < <(lines "$S/releases.tsv")
  return $rc
}
preview_dotfiles() {
  local f dest
  for f in $DOTFILES; do
    [[ -f $DATA/dotfiles/$f ]] || continue
    dest=$HOME/${f/#ssh\//.ssh/}
    [[ -f $dest ]] && say "would replace ${dest/#$HOME/~} (the old one is kept)" || say "would copy ${dest/#$HOME/~}"
  done
  say "would write $(grep -cv '^#' "$DATA/dotfiles/macos-defaults.tsv" 2>/dev/null || print 0) macOS settings"
}
preview_secrets() {
  local -a bundles; bundles=( "$DATA"/secrets/*.age(N) )
  (( ${#bundles} )) || { say "no encrypted bundle in ${DATA/#$HOME/~}/secrets: nothing to restore"; return 0; }
  say "would ask the passphrase and restore $(lines "$DATA/secrets/manifest.txt" | wc -l | tr -d ' ') files from ${bundles[1]:t}"
  [[ ! -x $HOOKS/after-secrets ]] || say "would run ${HOOKS/#$HOME/~}/after-secrets"
}
preview_repos() {
  local repo folder command n=0
  while IFS=$'\t' read -r repo folder command; do
    n=$((n + 1)); folder=${folder/#\~/$HOME}
    if [[ -d $folder/.git ]]; then say "ok      $repo"
    else say "would clone $repo into ${folder/#$HOME/~}$([[ $command != - ]] && print -r -- ", then run: $command")"; fi
  done < <(lines "$S/repos.tsv")
  (( n )) || say "no other projects in the list"
}
preview_jobs() {
  local label
  while read -r label; do
    launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1 && say "on      $label" || say "would register $label"
  done < <(lines "$S/jobs.txt")
}
preview_downloads() {
  local name url check
  while IFS=$'\t' read -r name url check; do
    check=${check/#\~/$HOME}
    have "$check" && say "ok      $name" || say "would open $url ($name)"
  done < <(lines "$S/downloads.tsv")
}
preview_check() { say "would scan this Mac and list what is still missing"; }

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
  if (( DRY )); then preview_$s || failed+=$s; else step_$s || failed+=$s; fi
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
(( DRY )) && { say "Dry run: nothing was installed or changed."; exit 0; }
say "Done. Last by hand: App Store sign-in, privacy permissions, app sign-ins, then the restore guides of tools that have their own."
