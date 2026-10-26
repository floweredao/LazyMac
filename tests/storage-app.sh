#!/bin/zsh
# Drive capacity uses rclone's local backend or a deliberately unconfigured remote.
set -euo pipefail
REPO=${0:A:h:h}
mkdir -p "$REPO/.work"
TMP=$(mktemp -d "$REPO/.work/storage-app.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
export LAZYMAC_STORAGE_CONF=$TMP/storage.conf LAZYMAC_DATA=$TMP/data LAZYMAC_HOST=Example-Mac RCLONE_CONFIG=$TMP/rclone.conf
cd "$REPO/app"
swift build -q
BIN=$(swift build --show-bin-path)/lazymac
mkdir -p "$TMP/storage"
printf 'backend local\nlocal %s\nfiles off\n' "$TMP/storage" > "$LAZYMAC_STORAGE_CONF"
fail=0
check() { if eval "$2"; then print "PASS $1"; else print "FAIL $1"; fail=1; fi; }
"$BIN" --storage-init example > "$TMP/out"
check "app starts from example into the overridden data folder" '[[ -f "$LAZYMAC_DATA/catalog.tsv" && -f "$LAZYMAC_DATA/setup/Brewfile" && -f "$TMP/storage/catalog.tsv" ]]'
check "app initialization assigns this Mac as main" 'grep -q $'"'"'Example-Mac\tmain\tpro'"'"' "$LAZYMAC_DATA/machines.tsv"'
check "example catalog render and check use the temporary data folder" \
  'bun "$REPO/bin/catalog.ts" render > "$TMP/catalog.out" && bun "$REPO/bin/catalog.ts" check >> "$TMP/catalog.out"'
"$BIN" --storage-status > "$TMP/status"
check "local capacity reports filesystem free space" 'jq -e ".available > 0 and .total >= .available and .stale == false" "$TMP/status" >/dev/null'

printf 'backend gdrive\nremote :local:%s\nfiles off\n' "$TMP/storage" > "$LAZYMAC_STORAGE_CONF"
"$BIN" --storage-status > "$TMP/status"
check "Drive capacity parses rclone about JSON without a real upload" 'jq -e ".available > 0 and .stale == false" "$TMP/status" >/dev/null'
target=:local:$TMP/storage
attempt=$(( $(date +%s) - 60 ))
printf '{"target":"%s","attemptedAt":%s,"available":17,"total":99,"stale":false}\n' "$target" "$attempt" > "$TMP/storage-status.json"
"$BIN" --storage-status > "$TMP/status"
check "capacity is cached for one day instead of querying on every view" \
  'jq -e --argjson attempt "$attempt" ".attemptedAt == \$attempt and .available == 17" "$TMP/status" >/dev/null'
zsh "$REPO/bin/storage.sh" upload
check "upload refreshes capacity even when the daily cache is fresh" \
  'jq -e --argjson attempt "$attempt" ".attemptedAt > \$attempt and .available != 17" "$TMP/storage-status.json" >/dev/null'

printf 'backend gdrive\nremote lazymac-unconfigured-test:LazyMac\nfiles off\n' > "$LAZYMAC_STORAGE_CONF"
printf '{"target":"lazymac-unconfigured-test:LazyMac","attemptedAt":0,"available":17,"total":99,"stale":false}\n' > "$TMP/storage-status.json"
"$BIN" --storage-status > "$TMP/status"
check "capacity failure preserves the last value and marks it stale" \
  'jq -e ".available == 17 and .total == 99 and .stale == true and .attemptedAt > 0" "$TMP/status" >/dev/null'
attempt=$(( $(date +%s) - 60 ))
jq --argjson attempt "$attempt" '.attemptedAt = $attempt' "$TMP/status" > "$TMP/storage-status.json"
"$BIN" --storage-status > "$TMP/status"
check "a failed capacity attempt is also cached for one day" \
  'jq -e --argjson attempt "$attempt" ".attemptedAt == \$attempt and .stale == true" "$TMP/status" >/dev/null'

printf 'backend local\nlocal %s\nfiles off\n' "$TMP/storage" > "$LAZYMAC_STORAGE_CONF"
export LAZYMAC_DATA=$TMP/restored
"$BIN" --storage-init restore > "$TMP/out"
check "app restores an empty data folder from storage" 'cmp "$TMP/data/catalog.tsv" "$TMP/restored/catalog.tsv"'
exit $fail
