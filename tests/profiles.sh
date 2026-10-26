#!/bin/zsh
# Profiles: `pro` gives exactly setup/, add-ons change only what they name, mistakes stop with exit 2,
# and compare sorts a Mac's scan into missing / extra / same.
# Usage: tests/profiles.sh
set -euo pipefail
REPO=${0:A:h:h}
mkdir -p "$REPO/.work"
TMP=$(mktemp -d "$REPO/.work/profiles.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
source "$REPO/tests/fixtures.zsh"
seed_data
ct() { bun $REPO/bin/catalog.ts "$@"; }
fail=0
check() { if eval "$2"; then print "ok      $1"; else print "FAIL    $1"; fail=1; fi; }
code() { set +e; eval "$1" >$TMP/err 2>&1; local c=$?; set -e; print $c; }
body() { grep -v '^# Generated' "$1"; }

ct profile pro $TMP/pro >/dev/null
same=1
for f in Brewfile npm.txt bun.txt scripts.tsv releases.tsv downloads.tsv jobs.txt versions.env; do
  diff <(body $LAZYMAC_DATA/setup/$f) <(body $TMP/pro/$f) >/dev/null || { print "differs $f"; same=0; }
done
check "profile pro writes the same lists as setup/" "(( same ))"

ct profile air,light $TMP/al >/dev/null
check "air drops the main-Mac-only jobs" "! grep -qx local.lazymac-daily $TMP/al/jobs.txt && grep -qx local.lazymac-daily $TMP/pro/jobs.txt"
check "light drops the coding groups and keeps the rest" "! grep -q '\"colima\"' $TMP/al/Brewfile && grep -q '\"colima\"' $TMP/pro/Brewfile && grep -q '\"gh\"' $TMP/al/Brewfile"

P=$TMP/profiles
mkdir -p $P
export LAZYMAC_PROFILES_DIR=$P
print -- 'from empty\n+ group cli/rust' > $P/rust.txt
ct profile rust $TMP/rust >/dev/null
check "+ group brings its keep rows but not a leave row" "grep -q '\"rust-analyzer\"' $TMP/rust/Brewfile && ! grep -q '\"rustup\"' $TMP/rust/Brewfile"
print -- 'from rust\n+ cli/rustup\nskip dotfiles secrets' > $P/rust2.txt
ct profile rust2 $TMP/rust2 >/dev/null
check "a named leave row comes in; skip lands in skip.txt" "grep -q '\"rustup\"' $TMP/rust2/Brewfile && [[ \$(grep -v '^#' $TMP/rust2/skip.txt | tr '\n' ' ') == 'dotfiles secrets ' ]]"
print -- '- cli/nothing-like-this' > $P/addon.txt
print -- 'from keep\n- app/no-such-app' > $P/badid.txt
print -- 'from loop2' > $P/loop1.txt; print -- 'from loop1' > $P/loop2.txt
print -- 'from keep\nskip dance' > $P/badstep.txt
check "an unknown item stops with exit 2" "[[ \$(code 'ct profile badid $TMP/x') == 2 ]] && grep -q 'no item app/no-such-app' $TMP/err"
check "an add-on used as the base stops with exit 2" "[[ \$(code 'ct profile addon $TMP/x') == 2 ]]"
check "a base used as an add-on stops with exit 2" "[[ \$(code 'ct profile rust,rust2 $TMP/x') == 2 ]]"
check "a from loop stops with exit 2" "[[ \$(code 'ct profile loop1 $TMP/x') == 2 ]] && grep -q 'loop' $TMP/err"
check "an unknown step stops with exit 2" "[[ \$(code 'ct profile badstep $TMP/x') == 2 ]]"
unset LAZYMAC_PROFILES_DIR

# compare: a made-up Mac without one keep app and with every other thing the Pro has.
export LAZYMAC_INVENTORY_DIR=$TMP/inv
mkdir -p $TMP/inv
seed_inventory "$TMP/inv/m"
app=$(awk -F'\t' '$1=="app" && $6=="keep" && $3 !~ /,/ {print $3}' $LAZYMAC_DATA/catalog.tsv | while read -r a; do if grep -q "^$a"$'\t' $TMP/inv/m/apps.tsv; then print -r -- $a; fi; done | sed -n 1p)
grep -v "^$app"$'\t' $TMP/inv/m/apps.tsv > $TMP/x; mv $TMP/x $TMP/inv/m/apps.tsv
ct compare pro --host m --json > $TMP/cmp.json
check "compare lists the missing keep app" "[[ \$(bun -e 'const j=await Bun.file(process.argv[1]).json();console.log(j.missing.map(i=>i.key).join(\",\"))' $TMP/cmp.json) == 'app/$app' ]]"
ct compare air,light --host m --json > $TMP/cmp2.json
check "compare shows what the profile leaves out as extra, never as missing" \
  "[[ \$(bun -e 'const j=await Bun.file(process.argv[1]).json();console.log(j.extra.some(i=>i.key===\"cli/colima\") && !j.missing.some(i=>i.key===\"cli/colima\"))' $TMP/cmp2.json) == true ]]"
check "compare with a Mac that has no scan stops with exit 2" "[[ \$(code 'ct compare pro --host nobody') == 2 ]]"
exit $fail
