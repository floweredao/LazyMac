#!/bin/zsh
# bin/settings.sh: saves the settings files setup.sh puts back, leaves out one that holds a secret, never deletes
# a saved copy, and refreshes the macOS settings list in place. A temporary home folder and a fake `defaults`;
# this Mac's real files and settings are never read. Usage: tests/settings.sh
set -euo pipefail
REPO=${0:A:h:h}
mkdir -p "$REPO/.work"
TMP=$(mktemp -d "$REPO/.work/settings.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
source "$REPO/tests/fixtures.zsh"
seed_data
export HOME=$TMP/home
fail=0
check() { if eval "$2"; then print "ok      $1"; else print "FAIL    $1"; sed 's/^/          /' "$TMP/out" | head -5; fail=1; fi; }
save() { zsh "$REPO/bin/settings.sh" save > "$TMP/out" 2>&1; }
D=$LAZYMAC_DATA/dotfiles

mkdir -p "$HOME/.ssh"
printf 'export EDITOR=nano\n' > "$HOME/.zshrc"
printf 'set -g mouse on\n' > "$HOME/.tmux.conf"
printf 'Host example\n  HostName example.com\n' > "$HOME/.ssh/config"
printf '//registry.npmjs.org/:_authToken=npm_%s\n' "$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 36)" > "$HOME/.npmrc"
printf 'not a setting LazyMac keeps\n' > "$HOME/.bashrc"
save
check "saves the settings files it knows, with ~/.ssh/config as ssh/config" \
  'cmp "$HOME/.zshrc" "$D/.zshrc" && cmp "$HOME/.tmux.conf" "$D/.tmux.conf" && cmp "$HOME/.ssh/config" "$D/ssh/config"'
check "leaves out a file that holds a secret and says so" '[[ ! -e $D/.npmrc ]] && grep -q "holds a secret: ~/.npmrc" "$TMP/out"'
check "saves only the listed files" '[[ ! -e $D/.bashrc ]]'
check "a new macOS settings list has the settings this Mac has set" \
  '[[ $(grep -v "^#" "$D/macos-defaults.tsv") == $'"'"'com.apple.dock\tautohide\tbool\ttrue\ncom.apple.dock\ttilesize\tfloat\t48\ncom.apple.finder\tShowPathbar\tbool\tfalse'"'"' ]]'
check "the summary counts files, settings and what was left out" '[[ $(tail -1 "$TMP/out") == "saved settings: 3 files, 3 macOS settings, 1 left out (secret)" ]]'

rm "$HOME/.tmux.conf"
printf 'export EDITOR=vim\n' > "$HOME/.zshrc"
printf '# my list\ncom.apple.dock\ttilesize\tint\t30\tkeep this note\ncom.example.app\tKnob\tbool\ttrue\n' > "$D/macos-defaults.tsv"
save
check "a changed file is saved again" '[[ $(<"$D/.zshrc") == "export EDITOR=vim" ]]'
check "a file this Mac no longer has keeps its saved copy" '[[ $(<"$D/.tmux.conf") == "set -g mouse on" ]]'
check "an existing list keeps its lines and notes and gets this Mac's values" \
  '[[ $(<"$D/macos-defaults.tsv") == $'"'"'# my list\ncom.apple.dock\ttilesize\tfloat\t48\tkeep this note\ncom.example.app\tKnob\tbool\ttrue'"'"' ]]'

# An empty string value leaves two tabs in a row; the note after it must stay a note.
printf '#!/bin/zsh\n[[ "$2/$3" == com.example.app/Title ]] || exec %s "$@"\n[[ $1 != read-type ]] || print "Type is string"\n' "$LAZYMAC_DEFAULTS" > "$TMP/defaults-empty"
chmod +x "$TMP/defaults-empty"
printf 'com.example.app\tTitle\tstring\t\tempty on purpose\n' > "$D/macos-defaults.tsv"
LAZYMAC_DEFAULTS=$TMP/defaults-empty save
check "an empty value keeps the note after it" \
  '[[ $(<"$D/macos-defaults.tsv") == $'"'"'com.example.app\tTitle\tstring\t\tempty on purpose'"'"' ]]'
exit $fail
