#!/bin/zsh
# Catch-up rules for the automatic backup. launchd starts the job at the scheduled times, at login (RunAtLoad) and
# every 30 minutes (StartInterval); each start runs `daily.sh --if-due`, which asks these functions whether a backup
# is due. A backup is due when the last success is older than the latest scheduled time (the "slot"), however many
# slots were missed, and at least half a period has passed since that success. After a failure it waits 15 minutes,
# then 30, 60 and 120 (never more than one period). It also waits while backups are paused, while the Mac is offline
# and, when the person asked for it, on a connection that may charge for data (hotspot, Low Data Mode).
#
# State lives in one "key value" file (LAZYMAC_STATE, default ~/Library/Application Support/lazymac/schedule-state):
#   last-success, last-attempt (epoch seconds), failures (in a row), notified (1 after the one alert of a bad stretch),
#   deferred (why the last automatic start waited), and from the app: paused (epoch), metered (wait), app (its binary).
# Sourced by daily.sh. The app's folder-only run uses the same rules through `zsh due.sh <command>`:
#   decide | net | start | ok | fail <reason>   (see the end of this file)
# Tests: LAZYMAC_NOW (epoch), LAZYMAC_NET (free|metered|offline), LAZYMAC_WAKETIME (epoch), LAZYMAC_LANG (en|ko).
zmodload zsh/datetime
DUE_STATE=${LAZYMAC_STATE:-$HOME/Library/Application Support/lazymac/schedule-state}
DUE_PLIST=${LAZYMAC_LAUNCHAGENTS_DIR:-$HOME/Library/LaunchAgents}/local.lazymac-daily.plist
DUE_PREV=0 DUE_PERIOD=0

due_now() { print -r -- ${LAZYMAC_NOW:-$EPOCHSECONDS}; }

state_get() {
  [[ -f $DUE_STATE ]] || return 0
  awk -v k="$1" '$1 == k { v = substr($0, length(k) + 2) } END { if (v != "") print v }' "$DUE_STATE"
}

# state_set <key> [value]: replaces the key's line; no value removes it. Written to a temp file and moved into place.
state_set() {
  mkdir -p "${DUE_STATE:h}"
  local tmp="$DUE_STATE.$$.tmp"
  {
    [[ ! -f $DUE_STATE ]] || awk -v k="$1" '$1 != k' "$DUE_STATE"
    [[ -z ${2:-} ]] || print -r -- "$1 $2"
  } > "$tmp" && mv -f "$tmp" "$DUE_STATE"
}

due_paused() { [[ -n $(state_get paused) ]]; }

# The latest time <= $4 that matches a calendar entry (weekday $1, hour $2, minute $3; "-" when the entry has none).
due_slot_before() {
  local w=$1 h=$2 m=$3 t=$4 day c wd noon back
  if [[ $h == - ]]; then
    strftime -s day '%Y-%m-%d %H' $t
    strftime -r -s c '%Y-%m-%d %H:%M' "$day:$m"
    (( c > t )) && (( c -= 3600 ))
    print -r -- $c
    return
  fi
  strftime -s day '%Y-%m-%d' $t
  strftime -r -s noon '%Y-%m-%d %H:%M' "$day 12:00"
  for back in {0..8}; do
    strftime -s day '%Y-%m-%d' $(( noon - back * 86400 ))
    strftime -r -s c '%Y-%m-%d %H:%M' "$day $h:$m"
    (( c > t )) && continue
    if [[ $w != - ]]; then
      strftime -s wd '%w' $c
      (( wd == w % 7 )) || continue
    fi
    print -r -- $c
    return
  done
}

# Reads StartCalendarInterval from the LaunchAgent and sets DUE_PREV (latest slot) and DUE_PERIOD (seconds).
# Fails when there is no schedule.
due_schedule() {
  local json now entries=() e w h m slot weekly=0 hours=0
  [[ -f $DUE_PLIST ]] || return 1
  json=$(plutil -extract StartCalendarInterval json -o - "$DUE_PLIST" 2>/dev/null) || return 1
  now=$(due_now)
  local close='}'
  entries=("${(@ps:$close:)json}")
  DUE_PREV=0
  local n=0
  for e in $entries; do
    [[ $e == *Minute* || $e == *Hour* ]] || continue
    w=- h=- m=0
    [[ $e =~ '"Weekday":([0-9]+)' ]] && { w=$match[1]; weekly=1; }
    [[ $e =~ '"Hour":([0-9]+)' ]] && { h=$match[1]; hours=1; }
    [[ $e =~ '"Minute":([0-9]+)' ]] && m=$match[1]
    slot=$(due_slot_before $w $h $m $now)
    (( slot > DUE_PREV )) && DUE_PREV=$slot
    n=$(( n + 1 ))
  done
  (( n > 0 )) || return 1
  if (( weekly )); then DUE_PERIOD=604800
  elif (( hours )); then DUE_PERIOD=$(( 86400 / n ))
  else DUE_PERIOD=3600; fi
}

# run | paused | notdue (the latest slot is done) | recent (less than half a period since the last success) |
# wait (waiting before trying again after a failure)
due_decide() {
  due_paused && { print paused; return; }
  due_schedule || { print run; return; }
  local now=$(due_now) last=$(state_get last-success) fails=$(state_get failures) att=$(state_get last-attempt)
  if [[ -n $last ]]; then
    (( last >= DUE_PREV )) && { print notdue; return; }
    (( now - last < DUE_PERIOD / 2 )) && { print recent; return; }
  fi
  fails=${fails:-0}
  if (( fails > 0 )) && [[ -n $att ]]; then
    (( fails > 4 )) && fails=4
    local wait=$(( 900 * 2 ** (fails - 1) )) cap=$DUE_PERIOD
    (( cap > 7200 )) && cap=7200
    (( wait > cap )) && wait=$cap
    (( now - att < wait )) && { print wait; return; }
  fi
  print run
}

# Seconds to wait so Wi-Fi can come back: 60 s after the Mac woke up.
due_wake_wait() {
  local wake=${LAZYMAC_WAKETIME:-} now=$(due_now)
  if [[ -z $wake ]]; then
    wake=$(sysctl -n kern.waketime 2>/dev/null)
    [[ $wake =~ 'sec = ([0-9]+)' ]] && wake=$match[1] || wake=0
  fi
  local since=$(( now - wake ))
  (( wake > 0 && since >= 0 && since < 60 )) && print $(( 60 - since )) || print 0
}

# free | metered | offline. The app answers through its --network-status (macOS knows hotspots and Low Data Mode);
# without the app, a missing default route means offline and the connection counts as free.
due_network() {
  local net=${LAZYMAC_NET:-} app
  if [[ -z $net ]]; then
    app=$(state_get app)
    [[ -n $app && -x $app ]] && net=$("$app" --network-status 2>/dev/null)
  fi
  if [[ $net != (free|metered|offline) ]]; then
    route -n get default >/dev/null 2>&1 && net=free || net=offline
  fi
  print -r -- $net
}

# Battery and power rules are not decided yet: every power state may back up.
due_power_ok() { return 0; }

due_korean() {
  local l=${LAZYMAC_LANG:-$(defaults read -g AppleLanguages 2>/dev/null | sed -n 2p)}
  [[ $l == *ko* ]]
}

due_since_phrase() {
  local secs=$1 n
  if (( secs >= 172800 )); then n=$(( secs / 86400 ))
    due_korean && print -r -- "${n}일" || print -r -- "$n days"
  else n=$(( secs / 3600 ))
    due_korean && print -r -- "${n}시간" || print -r -- "$n hours"
  fi
}

# due_alert failed|offline|metered [reason]: prints a notification text once per bad stretch (until the next
# success): after 3 failures in a row, or when the last success is more than two periods old.
due_alert() {
  due_schedule || return 0
  [[ -z $(state_get notified) ]] || return 0
  local kind=$1 reason=${2:-} now=$(due_now) last=$(state_get last-success) fails=$(state_get failures) overdue=0 since=""
  if [[ -n $last ]] && (( now - last > 2 * DUE_PERIOD )); then overdue=1; since=$(due_since_phrase $(( now - last ))); fi
  if [[ $kind == failed ]]; then (( ${fails:-0} >= 3 || overdue )) || return 0
  else (( overdue )) || return 0; fi
  state_set notified 1
  case $kind in
    failed)
      due_korean && print -r -- "자동 백업이 ${fails:-0}번 연달아 실패했어요: $reason. 계속 다시 해 볼게요." \
                 || print -r -- "The automatic backup failed ${fails:-0} times in a row: $reason. LazyMac keeps trying." ;;
    offline)
      due_korean && print -r -- "${since}째 백업을 못 했어요. 인터넷에 연결되면 바로 할게요." \
                 || print -r -- "No backup for $since. LazyMac backs up as soon as this Mac is online." ;;
    metered)
      due_korean && print -r -- "데이터 요금이 드는 연결이라 ${since}째 자동 백업을 미뤘어요. LazyMac을 열면 지금 백업할 수 있어요." \
                 || print -r -- "Automatic backups waited $since because this connection may charge for data. Open LazyMac to back up now." ;;
  esac
}

# Records why an automatic start waited; returns 0 the first time for that reason, so it is logged once.
due_defer() {
  [[ $(state_get deferred) == $1 ]] && return 1
  state_set deferred "$1"
}

due_started() { state_set last-attempt "$(due_now)"; }
due_succeeded() {
  state_set last-success "$(due_now)"; state_set failures; state_set notified; state_set deferred
}
due_failed() { local f=$(state_get failures); state_set failures $(( ${f:-0} + 1 )); }

# Command form for the app's folder-only run (no repo): prints what to do, one word, and for "net" an alert line.
if [[ $ZSH_EVAL_CONTEXT == toplevel ]]; then
  case ${1:-} in
    decide) d=$(due_decide); [[ $d != paused ]] || due_defer paused >/dev/null || true; print -r -- $d ;;
    net)
      net=$(due_network)
      if [[ $net == offline ]] || [[ $net == metered && $(state_get metered) == wait ]]; then
        due_defer $net || true
        print -r -- "skip $net"
        due_alert $net
      else print run; fi ;;
    start) due_started ;;
    ok) due_succeeded ;;
    fail) due_failed; due_alert failed "${2:-}" ;;
    *) print -u2 "usage: due.sh decide|net|start|ok|fail <reason>"; exit 2 ;;
  esac
fi
