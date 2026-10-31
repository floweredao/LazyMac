#!/bin/zsh
# lazymac inventory: re-generate the map of this Mac. READ-ONLY.
# It only lists things; it never installs, deletes, loads or unloads anything.
# It never reads secret values: launchd entries record only the program path,
# never arguments or environment variables. $HOME is written as "~".
#
# Usage: bin/inventory.sh [output-dir]      (default: <repo>/inventory/<host>, host = scutil --get LocalHostName
#                                           or LAZYMAC_HOST; each Mac keeps its own folder)
# Optional ~/.config/lazymac/inventory.conf (LAZYMAC_INVENTORY_CONF), one setting per line:
#   version <command>        also record `<command> --version` in versions.txt
#   skip-process <pattern>   leave resident programs whose path matches this extended regex out of processes.tsv
set -u
export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:$HOME/.bun/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_AUTO_UPDATE=1 LC_ALL=en_US.UTF-8

REPO=${0:A:h:h}
source "$REPO/bin/storage.sh"
HOST=${LAZYMAC_HOST:-$(scutil --get LocalHostName 2>/dev/null || hostname -s)}
OUT=${1:-$DATA/inventory/$HOST}
mkdir -p "$OUT"
PB=/usr/libexec/PlistBuddy
CONF=${LAZYMAC_INVENTORY_CONF:-$HOME/.config/lazymac/inventory.conf}
VERSIONS=(brew bun node npm uv git gh mas gitleaks)
SKIP='/CoreSimulator/|/target/(debug|release)/'
if [[ -f $CONF ]]; then
  while IFS= read -r line || [[ -n $line ]]; do
    read -r key val <<< "$line"
    [[ -z $key || $key == \#* ]] && continue
    case $key in
      version) VERSIONS+=("$val") ;;
      skip-process) SKIP+="|$val" ;;
      *) print -u2 -r -- "inventory.conf: unknown line: $line" ;;
    esac
  done < "$CONF"
fi
tilde() { sed "s#$HOME#~#g"; }
have() { command -v "$1" >/dev/null 2>&1; }
plist() { $PB -c "Print :$2" "$1" 2>/dev/null; }

# 1) Brewfile (formulae, casks, taps, App Store apps when `mas` is installed)
if have brew; then
  brew bundle dump --force --file="$OUT/Brewfile" >/dev/null 2>&1 \
    || print -u2 "warn: brew bundle dump failed"
  { print "# formula\tdescription"
    brew info --json=v1 $(brew leaves) 2>/dev/null | jq -r '.[] | "\(.full_name)\t\(.desc)"'
  } > "$OUT/brew-leaves.tsv"
fi

# 2) Applications with their source: mas | cask | manual | apple
casks_apps=""
if have brew && have jq; then
  casks_apps=$(brew info --cask --installed --json=v2 2>/dev/null \
    | jq -r '.casks[] | .token as $t | .artifacts[]? | objects | .app[]? | (if type == "string" then . else .target? // empty end) | split("/")[-1] | "\(.)\t\($t)"')
fi
{
  # Apps are identified by bundle id plus signing team id (team_id is "-" for unsigned or ad-hoc builds).
  print "# app\tsource\tcask\tversion\tbundle_id\tlocation\tteam_id"
  for app in /Applications/*.app ~/Applications/*.app(N); do
    name=${app:t}
    bid=$(plist "$app/Contents/Info.plist" CFBundleIdentifier)
    ver=$(plist "$app/Contents/Info.plist" CFBundleShortVersionString)
    cask=$(print -r -- "$casks_apps" | awk -F'\t' -v n="$name" '$1==n {print $2; exit}')
    if [[ -n $cask ]]; then src=cask
    elif [[ -d $app/Contents/_MASReceipt ]]; then src=mas
    elif [[ $bid == com.apple.* ]]; then src=apple
    else src=manual; fi
    team=$(codesign -dv "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p')
    [[ -z $team || $team == "not set" ]] && team=-
    print -r -- "${name%.app}	$src	$cask	$ver	$bid	${app:h}	$team"
  done | tilde
} > "$OUT/apps.tsv"
have mas && mas list 2>/dev/null | sed -E 's/[[:space:]]+/ /g' > "$OUT/mas.txt"

# 3) launchd jobs: user agents, system agents, system daemons (Apple's own are skipped)
loaded=$(launchctl list 2>/dev/null)
{
  print "# scope\tlabel\tstate\tprogram\tschedule\tplist"
  for dir scope in ~/Library/LaunchAgents user /Library/LaunchAgents system-agent /Library/LaunchDaemons system-daemon; do
    for p in $dir/*(N); do
      [[ -f $p ]] || continue
      label=$(plist "$p" Label); [[ -z $label ]] && label=${p:t:r}
      prog=$(plist "$p" Program); [[ -z $prog ]] && prog=$(plist "$p" ProgramArguments:0)
      sched=""
      [[ -n $(plist "$p" StartInterval) ]] && sched="every $(plist "$p" StartInterval)s"
      [[ -n $(plist "$p" StartCalendarInterval) ]] && sched="calendar"
      [[ $(plist "$p" KeepAlive) == true || -n $(plist "$p" KeepAlive:SuccessfulExit) ]] && sched="${sched:+$sched,}keepalive"
      [[ $(plist "$p" RunAtLoad) == true ]] && sched="${sched:+$sched,}atload"
      state=not-loaded
      if [[ $p != *.plist ]]; then state=disabled-file
      elif [[ $scope == user ]]; then
        line=$(print -r -- "$loaded" | awk -F'\t' -v l="$label" '$3==l {print $1; exit}')
        [[ -n $line ]] && { [[ $line == - ]] && state=loaded-idle || state=running; }
      else state=system; fi
      [[ -n $prog && ! -e $prog && $prog == /* ]] && state="$state,missing-program"
      print -r -- "$scope	$label	$state	$prog	$sched	$p"
    done
  done | tilde
} > "$OUT/launchd.tsv"

# 4) Resident programs not shipped by Apple: apps, Homebrew and home-folder binaries.
#    Simulator runtimes and build output are skipped as noise, plus any skip-process pattern.
{
  print "# program"
  ps -axo comm= | grep -E "^(/Applications/|/Library/Application Support/|/opt/homebrew/|$HOME/)" \
    | grep -vE "$SKIP" \
    | sed -E 's#(\.app)/.*#\1#; s#/Cellar/([^/]+)/[^/]+/#/Cellar/\1/*/#' | tilde | sort -u
} > "$OUT/processes.tsv"

# 5) Global command-line tools
{
  if have bun; then print "## bun (global)"; bun pm ls -g 2>/dev/null | tail -n +2 | sed -E 's/^[^a-zA-Z@]+//'; fi
  for nb in ~/.nvm/versions/node/*/bin(N); do
    print "## npm (node ${${nb:h}:t})"
    PATH=$nb:$PATH "$nb/npm" ls -g --depth=0 --json 2>/dev/null \
      | jq -r '.dependencies // {} | to_entries[] | "\(.key)@\(.value.version)"'
  done
  if have uv; then print "## uv tool"; uv tool list 2>/dev/null | grep -v '^-'; fi
  if have pipx; then print "## pipx"; pipx list --short 2>/dev/null; fi
  if have cargo; then print "## cargo install"; cargo install --list 2>/dev/null | grep -v '^ '; fi
} | tilde > "$OUT/cli-global.txt"

{
  print "# name\tlink_target_or_file"
  for f in ~/.local/bin/*(N); do
    if [[ -L $f ]]; then print -r -- "${f:t}	$(readlink "$f")"; else print -r -- "${f:t}	(file)"; fi
  done | tilde
} > "$OUT/local-bin.tsv"

# 6) Fonts installed for this user
ls ~/Library/Fonts 2>/dev/null > "$OUT/fonts.txt"

# 7) Tool versions
{
  print "macOS $(sw_vers -productVersion) ($(uname -m))"
  for c in $VERSIONS; do
    have $c && print -r -- "$c $($c --version 2>/dev/null | head -1)"
  done
} | tilde > "$OUT/versions.txt"

print "inventory written to ${OUT/#$HOME/~}"
wc -l "$OUT"/*.tsv "$OUT"/*.txt "$OUT"/Brewfile 2>/dev/null | tilde
