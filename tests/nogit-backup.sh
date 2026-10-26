#!/bin/zsh
# Folder backup: bin/nogit-backup.sh reads backup.conf, copies with rclone to a local folder standing in for the
# cloud, skips what it should, compares, lists, and restores without touching files that are already there.
# Runs in a temporary home folder; needs rclone. Usage: tests/nogit-backup.sh
set -u
REPO=${0:A:h:h}
mkdir -p "$REPO/.work"
TMP=$(mktemp -d "$REPO/.work/nogit.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
export LAZYMAC_DATA=$TMP/data LAZYMAC_STORAGE_CONF=$TMP/storage.conf
export HOME=$TMP/home LAZYMAC_BACKUP_CONF=$TMP/conf/backup.conf RCLONE_CONFIG=$TMP/rclone.conf
CLOUD=$TMP/cloud
S=$REPO/bin/nogit-backup.sh
fail=0
check() { if eval "$2"; then print "ok      $1"; else print "FAIL    $1"; sed 's/^/          /' $TMP/out | head -8; fail=1; fi; }
run() { zsh $S "$@" > $TMP/out 2>&1; }

mkdir -p $HOME/Documents/proj/node_modules/x $HOME/Documents/proj/sub $HOME/notes $TMP/outside $TMP/conf
print one > $HOME/Documents/proj/a.txt
print two > $HOME/Documents/proj/b.txt
print 'KEY=1' > $HOME/Documents/proj/.env
print 'KEY=' > $HOME/Documents/proj/.env.example
print dep > $HOME/Documents/proj/node_modules/x/i.js
print noise > $HOME/Documents/proj/run.log
print sub > $HOME/Documents/proj/sub/s.txt
git -C $HOME/Documents/proj/sub init -q && git -C $HOME/Documents/proj/sub remote add origin https://example.com/sub.git
print note > "$HOME/notes/my note.txt"
print far > $TMP/outside/o.txt

run rclone; c=$?
check "no backup.conf: stops with exit 2 and says how to set it up" "[[ $c == 2 ]] && grep -q 'not set up' $TMP/out"

print -r -- "# test
remote :local:$CLOUD
folder ~/Documents/proj/
folder ~/notes
folder $TMP/outside
exclude *.log" > $LAZYMAC_BACKUP_CONF

run list
check "list shows every folder" "[[ \$(grep -c . $TMP/out) == 3 ]] && grep -q 'skip-repos: sub' $TMP/out"
run rclone; c=$?
check "backup exits 0" "[[ $c == 0 ]]"
check "files land under <remote>/<path in home>" "[[ -f $CLOUD/Documents/proj/a.txt && -f '$CLOUD/notes/my note.txt' ]]"
check "a folder outside home lands under _root" "[[ -f $CLOUD/_root$TMP/outside/o.txt ]]"
check ".env.example is kept" "[[ -f $CLOUD/Documents/proj/.env.example ]]"
check "skips .env, node_modules, a repo with a remote and the extra pattern" \
  "[[ ! -e $CLOUD/Documents/proj/.env && ! -e $CLOUD/Documents/proj/node_modules && ! -e $CLOUD/Documents/proj/sub && ! -e $CLOUD/Documents/proj/run.log ]]"
check "writes the folder list" "[[ \$(cat $CLOUD/lazymac-folders.txt) == \$'Documents/proj\nnotes\n_root$TMP/outside' ]]"
check "records the run" "[[ \$(tail -1 $TMP/conf/runs.tsv | cut -f2-4) == \$'backup\tok\t:local:$CLOUD' ]]"

run rclone --check; c=$?
check "check after a backup passes" "[[ $c == 0 ]] && [[ \$(tail -1 $TMP/conf/runs.tsv | cut -f2,3) == \$'check\tok' ]]"
print changed > $HOME/Documents/proj/a.txt
run rclone --check; c=$?
check "check finds a changed file" "[[ $c == 1 ]] && [[ \$(tail -1 $TMP/conf/runs.tsv | cut -f2,3) == \$'check\tfailed' ]]"

run folders
check "folders prints the list from the cloud" "[[ \$(cat $TMP/out) == \$'Documents/proj\nnotes\n_root$TMP/outside' ]]"

run restore --to $TMP/back; c=$?
check "restore --to puts every folder under that folder" "[[ $c == 0 && \$(cat $TMP/back/Documents/proj/a.txt) == one && -f '$TMP/back/notes/my note.txt' ]]"
rm $HOME/Documents/proj/b.txt
run restore Documents/proj; c=$?
check "restore brings back a deleted file" "[[ $c == 0 && \$(cat $HOME/Documents/proj/b.txt) == two ]]"
check "restore leaves a file that is already here alone" "[[ \$(cat $HOME/Documents/proj/a.txt) == changed ]]"
touch -t 200001010000 $HOME/Documents/proj/a.txt
run restore --replace Documents/proj
check "restore --replace replaces an older file" "[[ \$(cat $HOME/Documents/proj/a.txt) == one ]]"
check "restore is recorded" "[[ \$(tail -1 $TMP/conf/runs.tsv | cut -f2,3) == \$'restore\tok' ]]"

rm -rf $HOME/notes
run rclone; c=$?
check "a missing folder fails the run and says so" "[[ $c == 1 ]] && grep -q 'MISSING: ~/notes' $TMP/out"

print -r -- "folder ~/Documents/proj" > $LAZYMAC_BACKUP_CONF
run rclone; c=$?
check "no remote: stops with exit 2" "[[ $c == 2 ]] && grep -q 'No cloud place' $TMP/out"

exit $fail
