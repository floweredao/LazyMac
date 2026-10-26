#!/bin/zsh
# prune must drop a catalog row only when it is gone from EVERY Mac in inventory/<host>/, and a Mac whose
# scan lacks a file must keep that kind. Runs on a copy of the repo with made-up scans.
# Usage: tests/hosts.sh
set -euo pipefail
REPO=${0:A:h:h}
mkdir -p "$REPO/.work"
TMP=$(mktemp -d "$REPO/.work/hosts.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
source "$REPO/tests/fixtures.zsh"
seed_data
printf 'host\trole\tprofiles\nExample-Mac\tmain\tpro\npro\tmain\tpro\n' > "$LAZYMAC_DATA/machines.tsv"
export LAZYMAC_INVENTORY_DIR=$TMP/inv
INV=$TMP/scan
seed_inventory "$INV"
mkdir -p $LAZYMAC_INVENTORY_DIR
cp -R $INV $LAZYMAC_INVENTORY_DIR/pro
cp -R $INV $LAZYMAC_INVENTORY_DIR/air
C=$LAZYMAC_DATA/catalog.tsv
fail=0
check() { if eval "$2"; then print "ok      $1"; else print "FAIL    $1"; fail=1; fi; }
has() { awk -F'\t' -v id="$1" '$3==id {f=1} END {exit !f}' $C; }
drop_app() { local h=$1; shift; for a in "$@"; do grep -v "^$a"$'\t' $LAZYMAC_INVENTORY_DIR/$h/apps.tsv > $TMP/x; mv $TMP/x $LAZYMAC_INVENTORY_DIR/$h/apps.tsv; done; }
prune() { bun $REPO/bin/catalog.ts prune --host pro >$TMP/out 2>&1; }

# Apps the scan sees only in apps.tsv (casks also show in Brewfile, App Store apps in mas.txt), and one npm tool.
apps=( ${(f)"$(awk -F'\t' '$1=="app" && $7!="cask" && $7!="mas" && $3 !~ /,/ {print $3}' $C | while read -r a; do if grep -q "^$a"$'\t' $INV/apps.tsv; then print -r -- $a; fi; done | sed -n 1,4p)"} )
npm=$(awk -F'\t' '$7=="npm" && $6=="keep" {print $8; exit}' $C)
A=${apps[1]} B=${apps[2]}

drop_app pro $A
prune
check "gone only from the Pro: $A stays" "has '$A'"
drop_app air $B
check "gone only from the Air: $B stays" "prune && has '$B'"
drop_app pro $B
check "gone from both Macs: $B goes" "prune && ! has '$B'"

grep -v "^$npm@" $LAZYMAC_INVENTORY_DIR/pro/cli-global.txt > $TMP/x; mv $TMP/x $LAZYMAC_INVENTORY_DIR/pro/cli-global.txt
rm $LAZYMAC_INVENTORY_DIR/air/cli-global.txt
check "the Air has no cli-global.txt: npm tool $npm stays" "prune && grep -q $'\t'$npm$'\t' $C"

: > $LAZYMAC_INVENTORY_DIR/pro/mas.txt
set +e; prune; code=$?; set -e
check "an empty scan file on this Mac makes prune refuse" "[[ $code == 1 ]] && grep -q 'empty or missing scan files: mas.txt' $TMP/out"
cp $INV/mas.txt $LAZYMAC_INVENTORY_DIR/pro/mas.txt

set +e; bun $REPO/bin/catalog.ts prune --host nobody >$TMP/out 2>&1; code=$?; set -e
check "no scan for this Mac makes prune refuse" "[[ $code == 1 ]]"

drop_app pro ${apps[3]} ${apps[4]}; drop_app air ${apps[3]} ${apps[4]}
set +e; LAZYMAC_PRUNE_LIMIT=1 prune; code=$?; set -e
check "more rows gone from every Mac than the limit makes prune refuse (nothing removed)" "[[ $code == 1 ]] && grep -q 'rows would go' $TMP/out && has '${apps[3]}'"
exit $fail
