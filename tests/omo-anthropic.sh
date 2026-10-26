#!/bin/zsh
# Test for bin/omo-anthropic.ts with a temporary Keychain file and a temporary omo folder,
# never the real ones. Uses fake keys and no network (the check command is not run).
set -euo pipefail
export PATH=$HOME/.bun/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
REPO=${0:A:h:h}
T=$(mktemp -d "${TMPDIR:-/tmp}/lazymac-omo-anthropic.XXXXXX")
export LAZYMAC_KEYCHAIN=$T/test.keychain-db LAZYMAC_OMO_AGENT=$T/agent
trap 'security delete-keychain "$LAZYMAC_KEYCHAIN" 2>/dev/null || true; rm -rf "$T"' EXIT INT TERM
fails=0
check() { if eval "$2"; then print "PASS $1"; else print "FAIL $1"; fails=$((fails + 1)); fi; }
tool() { bun "$REPO/bin/omo-anthropic.ts" "$@"; }

security create-keychain -p kc "$LAZYMAC_KEYCHAIN"; security unlock-keychain -p kc "$LAZYMAC_KEYCHAIN"
mkdir -p "$LAZYMAC_OMO_AGENT"
print -r -- '{"providers":{"other":{"api":"openai-completions"}}}' > "$LAZYMAC_OMO_AGENT/models.json"
print -r -- '{"other":{"type":"api_key","key":"keep-me"}}' > "$LAZYMAC_OMO_AGENT/auth.json"
chmod 600 "$LAZYMAC_OMO_AGENT/auth.json"
K1=sk-ant-usr-FAKEFLOWEREDAOKEY0000000000000000 K2=sk-ant-usr-FAKEMAINKEY00000000000000000000

check "sync with no keys fails"   '! tool sync >/dev/null 2>&1'
bad=$(print -rn -- not-a-key | tool add main 2>&1 || true)
check "bad key is refused"        '[[ $bad == *"Nothing was stored"* && -z $(tool list) ]]'
out=$(print -rn -- "$K1" | tool add floweredao; print -rn -- "$K2" | tool add main)
check "output never shows a key"  '[[ $out != *FAKE* ]]'
check "list puts main first"      '[[ $(tool list) == $'"'"'main\nfloweredao'"'"' ]]'

m=$LAZYMAC_OMO_AGENT/models.json a=$LAZYMAC_OMO_AGENT/auth.json
q() { bun -e "const j=JSON.parse(require('fs').readFileSync('$1','utf8')); console.log($2)"; }
check "provider added, others kept" '[[ $(q $m "Object.keys(j.providers).join()") == other,anthropic-api ]]'
check "provider has the models"     '[[ $(q $m "j.providers[\"anthropic-api\"].models.length") == 4 ]]'
check "accounts in order"           '[[ $(q $a "j[\"anthropic-api\"].accounts.map(x=>x.name).join()") == main,floweredao ]]'
check "keys match the Keychain"     '[[ $(q $a "j[\"anthropic-api\"].accounts.map(x=>x.key).join()") == "$K2,$K1" && $(q $a "j[\"anthropic-api\"].key") == $K2 ]]'
check "first account is pinned"    '[[ $(q $a "j[\"anthropic-api\"].pinned") == main ]]'
check "other auth entry kept"       '[[ $(q $a "j.other.key") == keep-me ]]'
check "auth.json stays mode 600"    '[[ $(stat -f %Lp $a) == 600 ]]'
check "backups are mode 600"        '[[ -z $(find $LAZYMAC_OMO_AGENT -name "auth.json.bak-lazymac-*" ! -perm 600) ]]'

n=$(ls $LAZYMAC_OMO_AGENT | wc -l | tr -d ' ')
again=$(tool sync)
check "second sync changes nothing" '[[ $again == *"already up to date, auth.json already up to date"* && $(ls $LAZYMAC_OMO_AGENT | wc -l | tr -d " ") == $n ]]'

(( fails == 0 )) && print "All passed." || { print "$fails failed."; exit 1; }
