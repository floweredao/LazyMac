#!/bin/zsh
# Round-trip test for bin/secrets-pack.sh and bin/secrets-restore.sh.
# Uses fake files in a temporary HOME and a temporary Keychain file, never the real
# ones. The test passphrase exists only inside this script; expect types it into age.
set -euo pipefail
export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
REPO=${0:A:h:h}
T=$(mktemp -d "${TMPDIR:-/tmp}/lazymac-test.XXXXXX")
KC1=$T/src.keychain-db KC2=$T/dst.keychain-db
cleanup() {
  security delete-keychain "$KC1" 2>/dev/null || true
  security delete-keychain "$KC2" 2>/dev/null || true
  rm -rf "$T"
}
trap cleanup EXIT INT TERM
export TEST_PW="roundtrip-test-only-$$"
fails=0
check() { if eval "$2"; then print "PASS $1"; else print "FAIL $1"; fails=$((fails + 1)); fi; }

# run_age <answer-count> <command...>: run under a pty and type TEST_PW at each age prompt
cat > "$T/run.exp" <<'EOF'
set timeout 60
set n [lindex $argv 0]
spawn -noecho {*}[lrange $argv 1 end]
for {set i 0} {$i < $n} {incr i} {
  expect {
    -re {passphrase[^:]*: } { send -- "$env(TEST_PW)\r" }
    eof { break }
  }
}
catch {expect eof}
catch wait r
exit [lindex $r 3]
EOF
run_age() { expect -f "$T/run.exp" -- "$@"; }

# 1) Fake source HOME and Keychain
H1=$T/home1 H2=$T/home2
mkdir -p "$H1/.omo/agent" "$H1/.config/gcloud/configurations" "$H1/.config/gcloud/logs" \
         "$H1/.ssh" "$H1/Library/Application Support/ExampleApp/data" "$H1/Library/Keychains"
print -r -- 'FAKEVALUE-omo-auth' > "$H1/.omo/agent/auth.json"
print -r -- 'FAKEVALUE-gcloud-cred' > "$H1/.config/gcloud/credentials.db"
print -r -- 'FAKEVALUE-gcloud-conf' > "$H1/.config/gcloud/configurations/config_default"
print -r -- 'noise' > "$H1/.config/gcloud/logs/run.log"
print -r -- 'FAKEVALUE-ssh-key' > "$H1/.ssh/id_ed25519"
print -r -- 'FAKEVALUE-app-cred' > "$H1/Library/Application Support/ExampleApp/data/credentials.json"
chmod 600 "$H1/.omo/agent/auth.json" "$H1/.ssh/id_ed25519"; chmod 700 "$H1/.ssh"
security create-keychain -p kc "$KC1"; security unlock-keychain -p kc "$KC1"
security create-keychain -p kc "$KC2"; security unlock-keychain -p kc "$KC2"
security add-generic-password -a me -s example-api -w 'FAKEVALUE "quoted" $x' "$KC1"
security add-generic-password -a me -s gemini-api -w 'FAKEVALUE-gemini' "$KC1"
security add-generic-password -a bin -s example-dot -X 00ff10414243 "$KC1"
security add-generic-password -a txt -s example-dot -w 'FAKEVALUE-dot' "$KC1"
security add-generic-password -a me -s not-in-manifest -w 'FAKEVALUE-other' "$KC1"

# Test manifest (the real one is personal data and is not in this repo)
export LAZYMAC_MANIFEST=$T/manifest.txt
print -r -- '.omo/agent/auth.json
.ssh/id_ed25519
.config/gcloud
exclude:.config/gcloud/logs
Library/Application Support/ExampleApp/data/credentials.json
keychain:example-*
keychain:gemini-api' > "$LAZYMAC_MANIFEST"

# 2) Dry run: names only
dry=$(HOME=$H1 LAZYMAC_KEYCHAIN=$KC1 LAZYMAC_SECRETS_OUT=$T/b.age "$REPO/bin/secrets-pack.sh" --dry-run)
check "dry-run lists a path"            '[[ $dry == *"~/.omo/agent/auth.json"* && $dry == *"~/.ssh/id_ed25519"* ]]'
check "dry-run folder count skips logs" '[[ $dry == *"~/.config/gcloud/  (folder, 2 files)"* ]]'
check "dry-run lists Keychain services" '[[ $dry == *"example-dot (x2)"* && $dry == *gemini-api* ]]'
check "dry-run prints no values"        '[[ $dry != *FAKEVALUE* && $dry != *00ff10* ]]'
check "dry-run writes nothing"          '[[ ! -e $T/b.age ]]'

# 3) Pack
HOME=$H1 LAZYMAC_KEYCHAIN=$KC1 LAZYMAC_SECRETS_OUT=$T/b.age run_age 2 "$REPO/bin/secrets-pack.sh" > "$T/pack.log"
check "pack makes an age file"          '[[ $(head -c 21 $T/b.age) == age-encryption.org/v1 ]]'
check "bundle has no plain text"        '! grep -aq FAKEVALUE $T/b.age'
check "pack log has no values"          '! grep -aq -e FAKEVALUE -e "$TEST_PW" $T/pack.log'
check "no temp stage left"              '[[ -z $(print -r -- ${TMPDIR:-/tmp}/lazymac-pack.*(N)) ]]'

# 4) Wrong passphrase changes nothing
mkdir -p "$H2"
TEST_PW=wrong HOME=$H2 LAZYMAC_KEYCHAIN=$KC2 run_age 1 "$REPO/bin/secrets-restore.sh" "$T/b.age" > "$T/bad.log" 2>&1 && rc=0 || rc=$?
check "wrong passphrase fails"          '(( rc != 0 ))'
check "wrong passphrase writes nothing" '[[ -z $(ls -A $H2) ]]'

# 5) Restore into a fresh HOME with one conflicting file
mkdir -p "$H2/.omo/agent"; print -r -- 'old' > "$H2/.omo/agent/auth.json"
HOME=$H2 LAZYMAC_KEYCHAIN=$KC2 run_age 1 "$REPO/bin/secrets-restore.sh" "$T/b.age" > "$T/restore.log"
for f in .omo/agent/auth.json .config/gcloud/credentials.db .config/gcloud/configurations/config_default \
         .ssh/id_ed25519 "Library/Application Support/ExampleApp/data/credentials.json"; do
  check "restored $f"                   "cmp -s \"$H1/$f\" \"$H2/$f\""
  check "mode of $f has no group/other" "[[ \$(stat -f %Lp \"$H2/$f\") == [67]00 ]]"
done
check "excluded logs not restored"      '[[ ! -e $H2/.config/gcloud/logs ]]'
check "~/.ssh is 700"                   '[[ $(stat -f %Lp $H2/.ssh) == 700 ]]'
check "new folders are 700"             '[[ $(stat -f %Lp $H2/.config) == 700 ]]'
check "conflict backed up"              '[[ $(cat $H2/.local/share/lazymac/restore-backup-*/.omo/agent/auth.json) == old ]]'
check "keychain text value"             '[[ $(security find-generic-password -s example-api -a me -w $KC2) == "FAKEVALUE \"quoted\" \$x" ]]'
check "keychain second value"           '[[ $(security find-generic-password -s gemini-api -a me -w $KC2) == FAKEVALUE-gemini ]]'
check "keychain binary value"           '[[ $(security find-generic-password -s example-dot -a bin -w $KC2) == 00ff10414243 ]]'
check "keychain same service, 2nd account" '[[ $(security find-generic-password -s example-dot -a txt -w $KC2) == FAKEVALUE-dot ]]'
check "unlisted keychain item left out" '! security find-generic-password -s not-in-manifest $KC2 >/dev/null 2>&1'
check "restore log has no values"       '! grep -aq -e FAKEVALUE -e "$TEST_PW" $T/restore.log'
check "no temp stage left"              '[[ -z $(print -r -- ${TMPDIR:-/tmp}/lazymac-restore.*(N)) ]]'

# 6) --list shows names only and changes nothing
lst=$(HOME=$T/home3 run_age 1 "$REPO/bin/secrets-restore.sh" --list "$T/b.age")
check "--list shows paths and services" '[[ $lst == *"~/.ssh/id_ed25519"* && $lst == *example-api* ]]'
check "--list prints no values"         '[[ $lst != *FAKEVALUE* ]]'
check "--list writes nothing"           '[[ ! -e $T/home3 ]]'

print; (( fails == 0 )) && print "ALL PASS" || { print "$fails FAILED"; exit 1; }
