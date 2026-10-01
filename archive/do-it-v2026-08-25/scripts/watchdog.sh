#!/bin/bash
# do-it fresheyes watchdog — bounded, liveness-watched fresheyes runner.
#
# Usage:   watchdog.sh <fresheyes.sh path> [args passed through to fresheyes.sh...]
# Prints exactly one status line at the end:
#   FRESHEYES_DONE OUT=<stdout file> LOG=<codex log>
#   FRESHEYES_STALLED OUT=<stdout file> LOG=<codex log or ->
# Always exits 0 — status is in the printed line, so background runners never
# mistake a stall for a crash. On STALLED: retry ONCE, then fall back to a
# fresh general-purpose subagent reviewer. Never retry a third time.
#
# When extracting the review, read LOG if OUT is empty — a flat-timer kill can
# leave OUT unwritten while the full review sits in the codex log (find the
# last "## Files Examined" through end).
#
# Tunables (env):
#   FE_CEILING        hard ceiling per attempt, seconds (default 1200 = 20 min;
#                     healthy high-reasoning reviews run 5-15 min)
#   FE_FLAT_TOLERANCE seconds of zero log growth before declaring a stall
#                     (default 420 — high-reasoning models go log-silent for
#                     minutes while composing; do NOT tighten below 420)
#   FE_LOG_WAIT       max seconds to wait for the codex log to appear (default 180)
#   FE_TICK           poll interval, seconds (default 15)
#
# Design notes (each one paid for with a real outage; keep):
# - fresheyes.sh BUFFERS stdout: OUT stays 0 bytes for the entire healthy run.
#   Liveness lives in the codex log under $TMPDIR/fresheyes-logs/. Watching
#   stdout for growth false-positives a stall on every single run.
# - A review can COMPLETE (verdict written to the log) and then sit idle,
#   tripping a naive flat-timer on an already-DONE run. Check for the verdict
#   BEFORE the flat-timer every tick; verdict-present is DONE, full stop.
# - Log discovery is by mtime marker (-newer), not `ls -t | head -1` — a fixed
#   sleep races stale/concurrent logs and false-stalls slow codex launches.
# - stdin MUST be </dev/null: codex hangs forever reading a non-TTY stdin pipe.
# - Teardown is process-group-scoped ONLY (kill -- -$PID). NEVER pkill by
#   pattern — that murders every codex/fresheyes process on the machine,
#   including sessions the user is running elsewhere.

set -u
FE_SH="${1:?usage: watchdog.sh <fresheyes.sh path> [fresheyes args...]}"; shift
CEILING="${FE_CEILING:-1200}"
FLAT_TOL="${FE_FLAT_TOLERANCE:-420}"
LOG_WAIT="${FE_LOG_WAIT:-180}"
TICK="${FE_TICK:-15}"

OUT="$(mktemp "${TMPDIR:-/tmp}/fresheyes-out.XXXXXX")"
MARK="$(mktemp "${TMPDIR:-/tmp}/fresheyes-mark.XXXXXX")"  # mtime marker: find THIS run's log
LOGDIR="${TMPDIR:-/tmp}/fresheyes-logs"
LOG=""

set -m
"$FE_SH" "$@" >"$OUT" 2>&1 </dev/null &
FE_PID=$!    # with set -m this is also the process-group id
set +m
disown "$FE_PID" 2>/dev/null || true   # keep job-control "Terminated" noise out of output

finish() { printf '%s OUT=%s LOG=%s\n' "$1" "$OUT" "${LOG:--}"; rm -f "$MARK"; exit 0; }

verdict_present() {
  { [ -n "$LOG" ] && grep -qE "INDEPENDENT CODE REVIEW (PASSED|FAILED)" "$LOG" 2>/dev/null; } \
    || grep -qE "INDEPENDENT CODE REVIEW (PASSED|FAILED)" "$OUT" 2>/dev/null
}

kill_group() { kill -TERM -- "-$FE_PID" 2>/dev/null; sleep 2; kill -KILL -- "-$FE_PID" 2>/dev/null; }

# Phase 1 — wait for this run's codex log to appear
waited=0
while [ -z "$LOG" ] && [ "$waited" -lt "$LOG_WAIT" ] && kill -0 "$FE_PID" 2>/dev/null; do
  sleep 5; waited=$((waited+5))
  LOG=$(find "$LOGDIR" -name '*.log' -newer "$MARK" 2>/dev/null | head -1)
done
if [ -z "$LOG" ]; then
  # Process exited fast (verdict may be in OUT) or never produced a log = broken launch
  if verdict_present; then finish FRESHEYES_DONE; fi
  kill_group; finish FRESHEYES_STALLED
fi

# Phase 2 — watch the LOG for liveness; verdict check outranks the flat-timer
deadline=$(( $(date +%s) + CEILING ))
last_size=-1; flat=0; stalled=0
while kill -0 "$FE_PID" 2>/dev/null; do
  sleep "$TICK"
  now=$(date +%s); size=$(wc -c <"$LOG" 2>/dev/null || echo 0)
  if [ "$size" = "$last_size" ]; then flat=$((flat+TICK)); else flat=0; fi
  last_size=$size
  if verdict_present; then break; fi
  if [ "$flat" -ge "$FLAT_TOL" ] || [ "$now" -ge "$deadline" ]; then stalled=1; break; fi
done

if verdict_present; then
  kill_group          # reap the idle process group; the review is done
  finish FRESHEYES_DONE
elif [ "$stalled" = 1 ]; then
  kill_group
  finish FRESHEYES_STALLED
else
  wait "$FE_PID" 2>/dev/null
  if verdict_present; then finish FRESHEYES_DONE; else finish FRESHEYES_STALLED; fi
fi
