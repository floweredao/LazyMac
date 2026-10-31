#!/bin/zsh
# bin/inventory.sh: the default tool list and process filter fit any Mac, and ~/.config/lazymac/inventory.conf adds
# `version <command>` and `skip-process <pattern>` lines. Runs with a temporary HOME and stand-ins for ps and
# codesign, so the resident-program list is fixed and no app is inspected.
# Usage: tests/inventory-conf.sh
set -euo pipefail
REPO=${0:A:h:h}
mkdir -p "$REPO/.work"
TMP=$(mktemp -d "$REPO/.work/inventory-conf.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
fail=0
check() { if eval "$2"; then print "ok      $1"; else print "FAIL    $1"; fail=1; fi; }

B=$TMP/home/.local/bin
mkdir -p $B
print -r -- '#!/bin/zsh
print -r -- "$HOME/Documents/proj/bin/app"
print -r -- "/Applications/Example.app/Contents/MacOS/Example"
print -r -- "$HOME/Library/Developer/CoreSimulator/Devices/x/bin/sim"
print -r -- "$HOME/code/proj/target/release/app"' > $B/ps
print -r -- '#!/bin/zsh
exit 0' > $B/codesign
print -r -- '#!/bin/zsh
print "example-tool 1.2.3"' > $B/example-tool
chmod +x $B/ps $B/codesign $B/example-tool
export HOME=$TMP/home LAZYMAC_DATA=$TMP/data LAZYMAC_STORAGE_CONF=$TMP/storage.conf
inventory() { zsh "$REPO/bin/inventory.sh" $TMP/$1 >/dev/null 2>$TMP/$1.err; }

inventory plain
check "no conf: a program under ~/Documents is listed"   'grep -qx "~/Documents/proj/bin/app" $TMP/plain/processes.tsv'
check "no conf: simulator and build output stay out"     '! grep -qE "CoreSimulator|target/release" $TMP/plain/processes.tsv'
check "no conf: only the built-in tools get a version"   '! grep -q example-tool $TMP/plain/versions.txt'

mkdir -p $HOME/.config/lazymac
print -r -- '# extras for this Mac
version example-tool
skip-process /Documents/
colour blue' > $HOME/.config/lazymac/inventory.conf
inventory conf
check "a version line adds that tool"                    'grep -qx "example-tool example-tool 1.2.3" $TMP/conf/versions.txt'
check "a skip-process line leaves matching programs out" '! grep -q Documents $TMP/conf/processes.tsv && grep -q Example.app $TMP/conf/processes.tsv'
check "an unknown line is reported"                      'grep -q "inventory.conf: unknown line: colour blue" $TMP/conf.err'

exit $fail
