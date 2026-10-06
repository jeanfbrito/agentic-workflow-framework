#!/usr/bin/env bash
# ledger-append.sh -- lock-guarded, atomic append to a .localdev/workflow/
# ledger file (done.md or findings.md). Multiple background builders /
# Workflow-lane agents may append concurrently via Edit and lose updates on
# a naive read-modify-write; this script serializes appends with a portable
# mkdir-spinlock (no flock on macOS) so concurrent writers never interleave
# or fuse their blocks together.
#
# Usage: bash ledger-append.sh <done|findings>   (entry text read from stdin)
#        bash ledger-append.sh decision <phase> <decision> <why> <evidence> <result>
#
# - `decision` appends one TSV row (ISO-8601 UTC timestamp first) to
#   decisions.tsv, writing the header row when the file is empty or absent.
#   Cells are sanitized: tabs/newlines/CRs become spaces, and a cell starting
#   with = + - @ gets a leading ' so spreadsheets never run it as a formula.
# - Exits nonzero + stderr on an unknown target, or when .localdev/workflow/
#   doesn't exist in CWD (nothing to append to).
# - Empty stdin is a clean no-op (exit 0, nothing written) -- there's
#   nothing meaningful to append, and writing just a blank separator would
#   be pure noise.
# - Lock: mkdir .localdev/workflow/.<file>.lock, ~2s timeout (20 x 100ms
#   polls). A lock dir older than 60s is swept as stale (crashed holder)
#   before every acquire attempt. On timeout, STILL appends -- a rare
#   interleaved entry beats a silently dropped one -- and tags the entry
#   with a `<!-- lock-timeout -->` marker so it's easy to spot.
# - Always writes a leading blank-line separator before the entry so two
#   concurrent appends can never fuse into a single malformed line.

set -uo pipefail

TARGET="${1:-}"
case "$TARGET" in
  done)     FILE="done.md" ;;
  findings) FILE="findings.md" ;;
  decision) FILE="decisions.tsv" ;;
  *)
    echo "ledger-append.sh: unknown target '$TARGET' -- expected 'done', 'findings' or 'decision'" >&2
    exit 1
    ;;
esac

if [ "$TARGET" = "decision" ] && [ "$#" -ne 6 ]; then
  echo "ledger-append.sh: usage: ledger-append.sh decision <phase> <decision> <why> <evidence> <result>" >&2
  exit 1
fi

WORKFLOW_DIR=".localdev/workflow"
if [ ! -d "$WORKFLOW_DIR" ]; then
  echo "ledger-append.sh: $WORKFLOW_DIR not found in $(pwd) -- nothing to append to" >&2
  exit 1
fi

clean() {
  local v
  v=$(printf '%s' "$1" | tr '\t\n\r' '   ')
  case "$v" in
    =*|+*|-*|@*) printf "'%s" "$v" ;;
    *) printf '%s' "$v" ;;
  esac
}

if [ "$TARGET" = "decision" ]; then
  ROW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for cell in "${@:2}"; do
    ROW="$ROW"$'\t'"$(clean "$cell")"
  done
else
  ENTRY="$(cat)"
  if [ -z "$ENTRY" ]; then
    exit 0  # clean no-op -- nothing to append
  fi
fi

LEDGER_PATH="$WORKFLOW_DIR/$FILE"
LOCK_DIR="$WORKFLOW_DIR/.$FILE.lock"

MAX_MS=2000
POLL_MS=100
elapsed_ms=0
acquired=0
timeout_hit=0

while :; do
  # Sweep a stale lock (crashed/killed holder) before every attempt.
  if [ -d "$LOCK_DIR" ]; then
    lock_mtime=$(stat -f %m "$LOCK_DIR" 2>/dev/null || stat -c %Y "$LOCK_DIR" 2>/dev/null || echo "")
    if [ -n "$lock_mtime" ]; then
      lock_age=$(( $(date +%s) - lock_mtime ))
      if [ "$lock_age" -gt 60 ]; then
        rmdir "$LOCK_DIR" 2>/dev/null || rm -rf "$LOCK_DIR" 2>/dev/null
      fi
    fi
  fi

  if mkdir "$LOCK_DIR" 2>/dev/null; then
    acquired=1
    break
  fi

  if [ "$elapsed_ms" -ge "$MAX_MS" ]; then
    timeout_hit=1
    break
  fi

  sleep 0.1
  elapsed_ms=$((elapsed_ms + POLL_MS))
done

if [ "$TARGET" = "decision" ]; then
  if [ ! -s "$LEDGER_PATH" ]; then
    printf 'ts\tphase\tdecision\twhy\tevidence\tresult\n' >> "$LEDGER_PATH"
  fi
  printf '%s\n' "$ROW" >> "$LEDGER_PATH"
else
  BLOCK=$'\n'"$ENTRY"$'\n'
  if [ "$timeout_hit" -eq 1 ]; then
    BLOCK="${BLOCK}<!-- lock-timeout -->"$'\n'
  fi
  printf '%s' "$BLOCK" >> "$LEDGER_PATH"
fi

if [ "$acquired" -eq 1 ]; then
  rmdir "$LOCK_DIR" 2>/dev/null || rm -rf "$LOCK_DIR" 2>/dev/null
fi

exit 0
