#!/bin/zsh
# The app must turn the default choice (every keep item) into the same lists that
# `bun bin/catalog.ts render` writes into setup/, and a profile into the same lists that
# `bun bin/catalog.ts profile` writes. Only the header line may differ.
# Usage: tests/app-setup-files.sh   (builds the app with swift build first)
set -euo pipefail
REPO=${0:A:h:h}
cd "$REPO/app"
swift build -q
BIN=$(swift build --show-bin-path)/lazymac
mkdir -p "$REPO/.work"
TMP=$(mktemp -d "$REPO/.work/app-setup.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
source "$REPO/tests/fixtures.zsh"
seed_data
# Two rows name the same repo (cloned once) and one takes the default folder: how=repo becomes setup/repos.tsv.
printf 'cli\ttools\t%s\t%s\t\tkeep\trepo\t%s\tA repo\t저장소\tExample only\t예제 전용\n' \
  example-repo 'Example repo' 'example/repo#~/.local/share/repo#make install' \
  example-repo-cli 'Example repo CLI' 'example/repo' \
  example-other 'Example other' 'example/other' >> "$LAZYMAC_DATA/catalog.tsv"
bun "$REPO/bin/catalog.ts" render >/dev/null
fail=0
same() {
  local want=$1 got=$2 label=$3 f
  for f in Brewfile npm.txt bun.txt scripts.tsv releases.tsv repos.tsv downloads.tsv jobs.txt versions.env; do
    if diff <(grep -v '^# Generated' "$want/$f") <(grep -v '^# Generated' "$got/$f") >/dev/null; then
      print "ok      $label $f"
    else
      print "differs $label $f"; diff <(grep -v '^# Generated' "$want/$f") <(grep -v '^# Generated' "$got/$f") || true; fail=1
    fi
  done
}
"$BIN" --write-setup "$TMP/app" --repo "$LAZYMAC_DATA"
same "$LAZYMAC_DATA/setup" "$TMP/app" keep
for p in air,light,outside air,dev; do
  "$BIN" --write-setup "$TMP/app-$p" --repo "$LAZYMAC_DATA" --profile $p
  bun "$REPO/bin/catalog.ts" profile $p "$TMP/cli-$p" >/dev/null
  same "$TMP/cli-$p" "$TMP/app-$p" $p
done
set +e
"$BIN" --write-setup "$TMP/bad" --repo "$LAZYMAC_DATA" --profile light 2>/dev/null
code=$?
set -e
if [[ $code == 2 ]]; then print "ok      an add-on as the base stops with exit 2"; else print "FAIL    add-on as base gave exit $code"; fail=1; fi
exit $fail
