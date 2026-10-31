#!/bin/zsh
# `bin/setup.sh secrets` runs the optional after-secrets hook (~/.config/lazymac/hooks or LAZYMAC_HOOKS) once the
# bundle is restored, and only then. A copy of bin/ with a stand-in secrets-restore.sh runs under .work/, so no
# bundle, Keychain or passphrase is touched.
# Usage: tests/setup-hooks.sh
set -euo pipefail
REPO=${0:A:h:h}
mkdir -p "$REPO/.work"
TMP=$(mktemp -d "$REPO/.work/setup-hooks.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
fail=0
check() { if eval "$2"; then print "ok      $1"; else print "FAIL    $1"; fail=1; fi; }

mkdir -p $TMP/repo $TMP/setup $TMP/hooks $TMP/data
cp -R "$REPO/bin" $TMP/repo/bin
print -r -- '#!/bin/zsh
print restored >> "$LOG"; exit ${RESTORE_EXIT:-0}' > $TMP/repo/bin/secrets-restore.sh
chmod +x $TMP/repo/bin/secrets-restore.sh
print 'NODE_VERSION=0\nPYTHON_VERSION=0' > $TMP/setup/versions.env
mkdir -p $TMP/home
export HOME=$TMP/home LAZYMAC_SETUP_DIR=$TMP/setup LAZYMAC_HOOKS=$TMP/hooks LAZYMAC_DATA=$TMP/data LAZYMAC_STORAGE_CONF=$TMP/storage.conf LOG=$TMP/log
setup() { zsh $TMP/repo/bin/setup.sh "$@" > $TMP/out 2>&1; }

: > $LOG
check "no hook: the secrets step succeeds" 'setup secrets && [[ $(<$LOG) == restored ]]'

print -r -- '#!/bin/zsh
print hook >> "$LOG"' > $TMP/hooks/after-secrets
chmod +x $TMP/hooks/after-secrets
: > $LOG
check "the hook runs once, after the restore" 'setup secrets && [[ $(<$LOG) == $'"'"'restored\nhook'"'"' ]]'

: > $LOG
check "a failed restore skips the hook" '! RESTORE_EXIT=1 setup secrets && [[ $(<$LOG) == restored ]]'

print -r -- '#!/bin/zsh
exit 4' > $TMP/hooks/after-secrets
check "a failing hook marks the step as failed" '! setup secrets && grep -q "after-secrets hook failed" $TMP/out && grep -q "problems in: secrets" $TMP/out'

check "--dry-run names the hook and runs nothing" 'mkdir -p $TMP/data/secrets; : > $TMP/data/secrets/secrets.tar.age; : > $LOG; setup --dry-run secrets && grep -q "after-secrets" $TMP/out && [[ ! -s $LOG ]]'

exit $fail
