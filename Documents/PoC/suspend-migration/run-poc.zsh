#!/bin/zsh
# vphone-tier: build
set -euo pipefail

# PoC F1-F5: in-place freezing, NBD disks and cold migration of a vphone.
# Steps and expected results: README.md beside this script.
#
# Runs on a test Mac against an installed VPhone.bundle built from the
# feat/suspend-and-nbd branch, whose vphone-vm is already admitted by AMFI
# (the host's usual `vphone-escalator allow`). It never changes SIP, AMFI or
# any system setting, never uses sudo, and refuses machines named wecom*.

zmodload zsh/datetime

script=${0:t}

cli=${VPHONE_CLI:-vphone-cli}
library=${VPHONE_LIBRARY_ROOT:-$HOME/.vphone/machines}
out=${POC_OUT:-$PWD/poc-results-$(date +%Y%m%d-%H%M%S)}
boot_timeout=${POC_BOOT_TIMEOUT:-600}
mkdir -p "$out"

usage() {
  cat <<EOF
usage: $script <step> <machine> [args]

  preflight <machine>                 versions, layout, and the machine's storage report
  f1 <machine>                        same-Mac save/restore (validateSaveRestoreSupport first)
  f2-save <machine>                   Mac A: save state for the cross-Mac test (needs F1 supported)
  f2-restore <machine> <state-dir>    Mac B: try that state; expect VZErrorRestore permission denied
  f3 <machine> <nbd-url>              NBD disk: boot, outages shorter and longer than the timeout
  f4 <machine>                        timings: pause/resume, save/restore, stop + cold start,
                                      and the state-directory identity adoption rehearsal
  f5 <machine> <before|after>         WeCom test-account checklist around a freeze or migration

Environment: VPHONE_CLI (default vphone-cli), VPHONE_LIBRARY_ROOT, POC_OUT,
POC_BOOT_TIMEOUT (s, default 600), F1_FORCE=1 (also try --ignore-validation),
NBD_TIMEOUT (default 10), NBD_STOP_CMD / NBD_START_CMD (shell commands that
stop and start the NBD server, for F3's outages), NBD_FATAL_TEST=1.
Results go to \$POC_OUT (default ./poc-results-<time>).
EOF
  exit 64
}

log() { print -r -- "[$(date +%H:%M:%S)] $*" | tee -a "$out/poc.log" }
die() { log "ERROR: $*"; exit 1 }
result() { print -r -- "$1: $2" | tee -a "$out/results.txt" }

guard() {
  local name=$1
  [[ $name == wecom* ]] && die "refusing $name: the PoC runs on test machines only"
  [[ -f $library/$name/config.plist ]] || die "no machine $name in $library"
}

socket() { print -r -- "$library/$1/vphone.sock" }

# One JSON request line in, one reply line out.
request() {
  local name=$1 json=$2 wait=${3:-30}
  print -r -- "$json" | /usr/bin/nc -U -w "$wait" "$(socket $name)" 2>/dev/null | head -n 1
}

# Value at a key path of a JSON document on stdin (plutil reads JSON).
jget() { /usr/bin/plutil -extract "$1" raw -o - - 2>/dev/null || true }

running() { pgrep -f -- "--config $library/$1/config.plist" >/dev/null 2>&1 }

wait_ping() {
  local name=$1 limit=${2:-$boot_timeout} start=$SECONDS
  until request "$name" '{"t":"ping","screen":false}' 5 | grep -q '"ok":true'; do
    (( SECONDS - start > limit )) && return 1
    sleep 2
  done
  print $(( SECONDS - start ))
}

wait_gone() {
  local name=$1 limit=${2:-60} start=$SECONDS
  while running "$name"; do
    (( SECONDS - start > limit )) && return 1
    sleep 0.5
  done
}

launch_bg() {
  local name=$1 tag=$2; shift 2
  "$cli" vm launch "$name" --headless "$@" >"$out/$name-$tag.log" 2>&1 &
  print $!
}

restore_bg() {
  local name=$1 tag=$2; shift 2
  "$cli" vm restore-state "$name" "$@" --headless >"$out/$name-$tag.log" 2>&1 &
  print $!
}

springboard_pid() {
  request "$1" '{"t":"rpc","method":"processes.list","params":{"filter":"SpringBoard"},"screen":false}' 30 \
    | tee "$out/$1-springboard-$(date +%s).json" | grep -oE '"pid" *: *[0-9]+' | head -n 1 | grep -oE '[0-9]+' || true
}

stop_vm() {
  local name=$1
  running "$name" || return 0
  "$cli" vm stop "$name" >>"$out/$name-stop.log" 2>&1 || true
  wait_gone "$name" 60 || true
}

ensure_booted() {
  local name=$1 tag=$2
  if ! running "$name"; then
    log "launching $name"
    launch_bg "$name" "$tag" >/dev/null
  fi
  local t
  t=$(wait_ping "$name") || die "$name did not answer within ${boot_timeout}s; see $out/$name-$tag.log"
  log "$name answers vphoned ping (${t}s)"
}

# MARK: - preflight

step_preflight() {
  local name=$1
  guard "$name"
  log "macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n hw.model)"
  log "vphone-cli: $(command -v "$cli" || print "$cli")"
  "$cli" --version 2>/dev/null | tee -a "$out/poc.log" || true
  "$cli" vm storage "$name" --json | tee "$out/$name-storage.json"
  "$cli" vm info "$name" --json >"$out/$name-info.json"
  log "storage and info saved; machine running: $(running "$name" && print yes || print no)"
}

# MARK: - F1 same-Mac save/restore

step_f1() {
  local name=$1 before after t rc=0 frc=0
  guard "$name"
  ensure_booted "$name" f1-boot
  before=$(springboard_pid "$name")
  log "SpringBoard pid before: ${before:-?}"

  "$cli" vm save-state "$name" --check --json >"$out/f1-check.json" || rc=$?
  log "validateSaveRestoreSupport: $(jget save_restore.supported <"$out/f1-check.json") (exit $rc)"
  log "blockers: $(jget save_restore.summary <"$out/f1-check.json")"
  result F1.validate "$( (( rc == 0 )) && print supported || print "unsupported: $(jget save_restore.summary <"$out/f1-check.json")")"

  if (( rc != 0 )); then
    if [[ ${F1_FORCE:-0} == 1 ]]; then
      log "F1_FORCE=1: saving with --ignore-validation (then resume)"
      "$cli" vm save-state "$name" "$out/f1-forced-state" --then resume --ignore-validation --json \
        >"$out/f1-forced.json" 2>"$out/f1-forced.err" || frc=$?
      result F1.forced-save "$( (( frc == 0 )) && print "saved (unexpected)" || print "refused: $(tail -n 1 "$out/f1-forced.err")")"
      log "VM state after forced attempt: $(request "$name" '{"t":"vmstate"}' 10 | jget result.state)"
    fi
    stop_vm "$name"
    log "F1 ends: Virtualization refuses to save this configuration"
    return 0
  fi

  "$cli" vm save-state "$name" --replace --json >"$out/f1-save.json"
  log "saved: $(jget bytes <"$out/f1-save.json") bytes; pause $(jget pause_seconds <"$out/f1-save.json") s, save $(jget save_seconds <"$out/f1-save.json") s, stop $(jget after_seconds <"$out/f1-save.json") s"
  wait_gone "$name" 60 || die "vphone-vm still running after save-state"
  log "process gone; memory returned"

  restore_bg "$name" f1-restore >/dev/null
  t=$(wait_ping "$name") || die "no ping after restore-state"
  log "answers ${t}s after restore-state"
  grep -E "Restored in|Booting cold|Could not resume" "$out/$name-f1-restore.log" | tee -a "$out/poc.log" || true
  after=$(springboard_pid "$name")
  log "SpringBoard pid after: ${after:-?}"
  if grep -q "Restored in" "$out/$name-f1-restore.log" && [[ -n $before && $before == $after ]]; then
    result F1.restore "resumed (same SpringBoard pid $before, ping after ${t}s)"
  else
    result F1.restore "did NOT resume (see $out/$name-f1-restore.log)"
  fi
  "$cli" vm storage "$name" | grep "saved state" | tee -a "$out/poc.log"
  stop_vm "$name"
}

# MARK: - F2 cross-Mac

step_f2_save() {
  local name=$1
  guard "$name"
  ensure_booted "$name" f2-boot
  "$cli" vm save-state "$name" --check --json >"$out/f2-check.json" \
    || die "save/restore unsupported (see f2-check.json); F2 needs F1 to pass"
  "$cli" vm save-state "$name" --replace --json >"$out/f2-save.json"
  wait_gone "$name" 60 || true
  local state="$library/$name/SavedState"
  log "saved state at $state"
  log "next: copy the stopped machine to Mac B without the state (vm export / import, or rsync"
  log "of the folder), copy $state separately, then on B: $script f2-restore $name <copied-dir>"
  log "do NOT boot $name on A again before B has tried: that marks the state used"
}

step_f2_restore() {
  local name=$1 state=${2:-} rc=0
  guard "$name"
  [[ -n $state && -f $state/binding.plist ]] || die "pass the copied saved-state directory"
  running "$name" && die "$name is running"
  log "restoring a state saved on $(/usr/bin/plutil -extract hostName raw -o - "$state/binding.plist")"
  "$cli" vm restore-state "$name" "$state" --headless --no-cold-boot-fallback --restore-from-other-host \
    >"$out/$name-f2-restore.log" 2>&1 || rc=$?
  grep -E "Restoring|Could not resume|Restored in|VZErrorDomain|Code=" "$out/$name-f2-restore.log" | tee -a "$out/poc.log" || true
  if grep -q "Restored in" "$out/$name-f2-restore.log"; then
    result F2 "restored on another Mac (contradicts the header!)"
    stop_vm "$name"
  else
    result F2 "refused (exit $rc): $(grep -m1 -E 'Could not resume' "$out/$name-f2-restore.log" || print see log)"
  fi
}

# MARK: - F3 NBD

step_f3() {
  local name=$1 url=${2:-} original t outage timeout
  guard "$name"
  [[ $url == nbd://* ]] || die "pass the export as nbd://host:port/export"
  running "$name" && die "stop $name first"
  original=$("$cli" vm storage "$name" --json | jget disk)
  log "disk was $original; switching to $url"
  "$cli" vm storage "$name" --disk "$url" --nbd-timeout "${NBD_TIMEOUT:-10}" | tee -a "$out/poc.log"
  trap "log 'switching $name back to $original'; $cli vm storage $name --disk $original >/dev/null 2>&1 || true" EXIT

  ensure_booted "$name" f3-boot
  request "$name" '{"t":"vmstate","check":true}' 60 | tee "$out/f3-vmstate.json" >/dev/null
  log "nbd connected: $(jget result.nbd.connected <"$out/f3-vmstate.json"), connections $(jget result.nbd.connections <"$out/f3-vmstate.json")"
  log "save/restore with NBD (configuration level): $(jget result.save_restore.summary <"$out/f3-vmstate.json")"
  result F3.boot "booted from $url"

  if [[ -n ${NBD_STOP_CMD:-} && -n ${NBD_START_CMD:-} ]]; then
    timeout=${NBD_TIMEOUT:-10}
    for outage in $(( timeout / 2 )) $(( timeout * 3 )); do
      log "outage of ${outage}s (client timeout ${timeout}s)"
      eval "$NBD_STOP_CMD"
      sleep "$outage"
      eval "$NBD_START_CMD"
      if t=$(wait_ping "$name" 180); then
        request "$name" '{"t":"vmstate"}' 10 >"$out/f3-after-$outage.json"
        result "F3.outage-${outage}s" "guest answers ${t}s after the server came back; connections $(jget result.nbd.connections <"$out/f3-after-$outage.json")"
      else
        result "F3.outage-${outage}s" "guest does not answer within 180s"
      fi
      grep -E "^\[nbd\]" "$out/$name-f3-boot.log" | tail -n 5 | tee -a "$out/poc.log" || true
    done
    if [[ ${NBD_FATAL_TEST:-0} == 1 ]]; then
      log "stopping the NBD server for good; waiting up to 10 min for the client to give up"
      eval "$NBD_STOP_CMD"
      if wait_gone "$name" 600; then
        result F3.fatal "vphone-vm stopped: $(grep -m1 'lost .* for good' "$out/$name-f3-boot.log" || print 'no [nbd] lost line')"
      else
        result F3.fatal "still running after 10 min without its server"
      fi
      eval "$NBD_START_CMD"
    fi
  else
    log "NBD_STOP_CMD / NBD_START_CMD not set: outage tests skipped"
  fi
  stop_vm "$name"
}

# MARK: - F4 timings

step_f4() {
  local name=$1 t0 t1 t2 t s rc=0 udid_before udid_after config
  guard "$name"
  ensure_booted "$name" f4-boot

  t0=$EPOCHREALTIME
  request "$name" '{"t":"pause"}' 60 >/dev/null
  t1=$EPOCHREALTIME
  request "$name" '{"t":"resume"}' 60 >/dev/null
  t2=$EPOCHREALTIME
  result F4.pause "$(( t1 - t0 )) s"
  result F4.resume "$(( t2 - t1 )) s"

  "$cli" vm save-state "$name" --check --json >"$out/f4-check.json" || rc=$?
  if (( rc == 0 )); then
    "$cli" vm save-state "$name" --replace --json >"$out/f4-save.json"
    result F4.save "pause $(jget pause_seconds <"$out/f4-save.json") s, save $(jget save_seconds <"$out/f4-save.json") s, stop $(jget after_seconds <"$out/f4-save.json") s, $(jget bytes <"$out/f4-save.json") bytes"
    wait_gone "$name" 60 || true
    restore_bg "$name" f4-restore >/dev/null
    t=$(wait_ping "$name") || die "no ping after restore"
    result F4.restore "ping ${t}s after restore-state; $(grep -m1 'Restored in' "$out/$name-f4-restore.log" || print 'not resumed')"
  else
    result F4.save "skipped: save/restore unsupported"
  fi

  udid_before=$("$cli" vm info "$name" --json | jget udid)
  s=$SECONDS
  "$cli" vm stop "$name" >>"$out/$name-stop.log" 2>&1
  wait_gone "$name" 60 || true
  result F4.stop "$(( SECONDS - s )) s (guest shutdown, then the VM stops)"

  # Cold start with the identity taken from MachineState/identity.plist, as on
  # a target Mac whose config.plist was recreated without one.
  "$cli" vm storage "$name" --state-dir on >/dev/null
  config="$library/$name/config.plist"
  cp "$config" "$out/$name-config.plist.bak"
  /usr/bin/plutil -replace machineIdentifier -data "" "$config"
  launch_bg "$name" f4-cold >/dev/null
  t=$(wait_ping "$name") || die "no ping after the cold start"
  result F4.cold-start "ping ${t}s after vm launch"
  grep -m1 "Adopted the machine identity" "$out/$name-f4-cold.log" | tee -a "$out/poc.log" || true
  udid_after=$("$cli" vm info "$name" --json | jget udid)
  result F4.identity "UDID before $udid_before, after $udid_after ($([[ $udid_before == $udid_after ]] && print same || print DIFFERENT))"
  stop_vm "$name"
}

# MARK: - F5 WeCom test account

step_f5() {
  local name=$1 phase=${2:-} answer question
  guard "$name"
  [[ $phase == before || $phase == after ]] || die "phase is before or after"
  ensure_booted "$name" "f5-$phase"
  request "$name" "{\"t\":\"screenshot\",\"path\":\"$out/f5-$phase.png\",\"screen\":false}" 60 >/dev/null || true
  log "screenshot: $out/f5-$phase.png"
  for question in \
    "WeCom opens to the message list without asking to log in again" \
    "a message sent from another device arrives within a minute" \
    "no security prompt (new device / verify identity) appeared"; do
    read "answer?$phase: $question? [y/n/notes] "
    result "F5.$phase" "$question: $answer"
  done
}

(( $# >= 2 )) || usage
command=$1
shift
case $command in
  preflight) step_preflight "$@" ;;
  f1) step_f1 "$@" ;;
  f2-save) step_f2_save "$@" ;;
  f2-restore) step_f2_restore "$@" ;;
  f3) step_f3 "$@" ;;
  f4) step_f4 "$@" ;;
  f5) step_f5 "$@" ;;
  *) usage ;;
esac
log "results: $out/results.txt"
