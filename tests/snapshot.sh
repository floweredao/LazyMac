#!/bin/zsh
# The history page must show what changed between two days and must never publish private rows or words.
# Usage: tests/snapshot.sh
set -euo pipefail
REPO=${0:A:h:h}
mkdir -p "$REPO/.work"
TMP=$(mktemp -d "$REPO/.work/snapshot.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
source "$REPO/tests/fixtures.zsh"
seed_data
export LAZYMAC_SNAPSHOT_DIR=$TMP/snap
mkdir -p $LAZYMAC_SNAPSHOT_DIR
H=$'section\tgroup\tid\tname\tname_ko\tdecision\twhat_en\twhat_ko'
print -r -- "$H
app	ai	A	Alpha		keep	a	a
app	ai	B	Beta		keep	b	b
app	ai	C	Gamma		ask	c	c
secret	bundle	S	Hidden key list		keep	keys	keys
elsewhere	data	D	Budget data		keep	db	db" > $LAZYMAC_SNAPSHOT_DIR/2026-01-01.tsv
print -r -- "$H
app	dev	A	Alpha		keep	a	a
app	ai	C	Gamma		drop	c	c
app	ai	N	Newbie		keep	n	n
secret	bundle	S	Hidden key list		keep	keys	keys
elsewhere	data	D	Budget data		keep	db	db" > $LAZYMAC_SNAPSHOT_DIR/2026-01-02.tsv

fail=0
check() { if eval "$2"; then print "ok      $1"; else print "FAIL    $1"; fail=1; fi; }

bun $REPO/bin/snapshot.ts build $TMP/site >/dev/null
day=$TMP/site/data/2026-01-02.json
check "index lists both days, newest first" \
  "[[ \$(bun -e 'const j=await Bun.file(process.argv[1]).json();console.log(j.days.map(d=>d.date).join(\",\"))' $TMP/site/data/index.json) == 2026-01-02,2026-01-01 ]]"
# Alpha only moved to another subcategory on day 2: that is not a change.
check "added / removed / changed (a subcategory move alone is not a change)" \
  "[[ \$(bun -e 'const j=await Bun.file(process.argv[1]).json();console.log([j.added.map(i=>i.n),j.removed.map(i=>i.n),j.changed.map(i=>i.n+\":\"+i.from+\">\"+i.d)].join(\"|\"))' $day) == 'Newbie|Beta|Gamma:ask>drop' ]]"
check "index has the subcategory titles from groups.tsv, without secret or data ones" \
  "[[ \$(bun -e 'const j=await Bun.file(process.argv[1]).json();const k=j.groups.map(g=>g[0]+\"/\"+g[1]);console.log(k.includes(\"app/assistants\")&&!k.some(x=>x.startsWith(\"secret/\")||x===\"elsewhere/data\"))' $TMP/site/data/index.json) == true ]]"
check "secret and private data rows are left out" "! grep -rqE 'Hidden key list|Budget data' $TMP/site/data"
check "index.html is there" "[[ -s $TMP/site/index.html ]]"
# The four counts filter the whole list: a count shows only its kind, an empty kind says so, the total shows everything again.
check "pressing a count filters the list (aria-pressed follows)" \
  "[[ \$(bun $REPO/tests/history-filter.ts $TMP/site) == 'total:✅⛔✅|keep:✅✅|total:✅⛔✅|drop:⛔|ask:empty|total:✅⛔✅' ]]"

print -r -- "app	ai	P	Mail	 	keep	write to someone@example.com	x" >> $LAZYMAC_SNAPSHOT_DIR/2026-01-02.tsv
set +e
bun $REPO/bin/snapshot.ts build $TMP/site2 >/dev/null 2>&1
code=$?
set -e
check "a mail address makes build refuse (exit 5) and write nothing" "[[ $code == 5 && ! -e $TMP/site2 ]]"
exit $fail
