#!/bin/zsh
# The end of `bin/setup.sh secrets`, once the bundle is back: the optional omo provider sync (only on a Mac that
# keeps those Keychain keys, and never fatal) and the optional after-secrets hook (~/.config/lazymac/hooks, or
# LAZYMAC_HOOKS). A copy of bin/ runs under .work/ with stand-ins for secrets-restore.sh and bun, so no bundle,
# Keychain, passphrase or omo config is touched.
# Usage: tests/setup-hooks.sh
set -euo pipefail
REPO=${0:A:h:h}
mkdir -p "$REPO/.work"
TMP=$(mktemp -d "$REPO/.work/setup-hooks.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
fail=0
check() { if eval "$2"; then print "ok      $1"; else print "FAIL    $1"; fail=1; fi; }

mkdir -p $TMP/repo $TMP/setup $TMP/hooks $TMP/data $TMP/home/.bun/bin
cp -R "$REPO/bin" $TMP/repo/bin
print -r -- '#!/bin/zsh
print restored >> "$LOG"; exit ${RESTORE_EXIT:-0}' > $TMP/repo/bin/secrets-restore.sh
print -r -- '#!/bin/zsh
case ${2:-} in
  list) print -n -- "${KEYS:-}" ;;
  sync) print sync >> "$LOG"; exit ${SYNC_EXIT:-0} ;;
esac' > $TMP/home/.bun/bin/bun
chmod +x $TMP/repo/bin/secrets-restore.sh $TMP/home/.bun/bin/bun
print 'NODE_VERSION=0\nPYTHON_VERSION=0' > $TMP/setup/versions.env
export HOME=$TMP/home LAZYMAC_SETUP_DIR=$TMP/setup LAZYMAC_HOOKS=$TMP/hooks LAZYMAC_DATA=$TMP/data \
       LAZYMAC_STORAGE_CONF=$TMP/storage.conf LOG=$TMP/log
setup() { zsh $TMP/repo/bin/setup.sh "$@" > $TMP/out 2>&1; }
log_is() { [[ ${$(<$LOG)//$'\n'/ } == $1 ]] }

check "no keys and no hook: the step still succeeds" ': > $LOG; setup secrets && log_is restored'
check "the key sync runs once, after the restore"    ': > $LOG; KEYS=main setup secrets && log_is "restored sync"'
check "a failing key sync warns, the step stays ok"  ': > $LOG; KEYS=main SYNC_EXIT=1 setup secrets && grep -q "^warn" $TMP/out'

print -r -- '#!/bin/zsh
print hook >> "$LOG"' > $TMP/hooks/after-secrets
chmod +x $TMP/hooks/after-secrets
check "the hook runs after the restore"              ': > $LOG; setup secrets && log_is "restored hook"'
check "with keys: sync first, then the hook"         ': > $LOG; KEYS=main setup secrets && log_is "restored sync hook"'
check "a failed restore skips the sync and the hook" ': > $LOG; ! KEYS=main RESTORE_EXIT=1 setup secrets && log_is restored'

print -r -- '#!/bin/zsh
exit 4' > $TMP/hooks/after-secrets
check "a failing hook marks the step as failed"      '! setup secrets && grep -q "after-secrets hook failed" $TMP/out && grep -q "problems in: secrets" $TMP/out'
check "--dry-run names the hook and runs nothing"    'mkdir -p $TMP/data/secrets; : > $TMP/data/secrets/secrets.tar.age; : > $LOG; setup --dry-run secrets && grep -q after-secrets $TMP/out && [[ ! -s $LOG ]]'

exit $fail
