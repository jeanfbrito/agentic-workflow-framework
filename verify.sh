#!/usr/bin/env bash
# verify.sh -- Standalone verification for Agentic Workflow Framework
# Checks that the framework is correctly installed in ~/.claude/
# Prints [x] for pass, [ ] for fail. Exits 1 if any check fails.
# Can be run standalone after manual edits, or called by install.sh.

set -uo pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required but not found in PATH." >&2
  exit 1
fi

PASS=0
FAIL=1
ALL_PASS=1

check() {
  local desc="$1"
  local code="$2"
  if [ "$code" -eq 0 ]; then
    echo "[x] $desc"
  else
    echo "[ ] $desc"
    ALL_PASS=0
  fi
}

# ---------------------------------------------------------------------------
# Check 1 -- every repo framework file is installed in ~/.claude/
#            (list derived from repo contents, so new agents/commands are
#             covered automatically)
# ---------------------------------------------------------------------------

FILES=(
  ~/.claude/AGENTIC.md
  ~/.claude/hooks/orchestrator.sh
  ~/.claude/hooks/session-scan.sh
  ~/.claude/hooks/pre-compact.sh
  ~/.claude/hooks/stop-ledger-audit.sh
  ~/.claude/hooks/ledger-append.sh
  ~/.claude/hooks/skill-review-nudge.sh
)
for f in "$SCRIPT_DIR"/agents/*.md; do
  FILES+=( ~/.claude/agents/"$(basename "$f")" )
done
for f in "$SCRIPT_DIR"/commands/*.md; do
  FILES+=( ~/.claude/commands/"$(basename "$f")" )
done
ALL_FILES=0
for f in "${FILES[@]}"; do
  [ -f "$f" ] || { ALL_FILES=1; break; }
done
check "${#FILES[@]} framework files exist in ~/.claude/" "$ALL_FILES"

# ---------------------------------------------------------------------------
# Check 2 -- orchestrator.sh is executable
# ---------------------------------------------------------------------------

if test -x ~/.claude/hooks/orchestrator.sh; then
  check "orchestrator.sh is executable" "$PASS"
else
  check "orchestrator.sh is executable" "$FAIL"
fi

if test -x ~/.claude/hooks/session-scan.sh; then
  check "session-scan.sh is executable" "$PASS"
else
  check "session-scan.sh is executable" "$FAIL"
fi

if test -x ~/.claude/hooks/pre-compact.sh; then
  check "pre-compact.sh is executable" "$PASS"
else
  check "pre-compact.sh is executable" "$FAIL"
fi

if test -x ~/.claude/hooks/stop-ledger-audit.sh; then
  check "stop-ledger-audit.sh is executable" "$PASS"
else
  check "stop-ledger-audit.sh is executable" "$FAIL"
fi

if test -x ~/.claude/hooks/ledger-append.sh; then
  check "ledger-append.sh is executable" "$PASS"
else
  check "ledger-append.sh is executable" "$FAIL"
fi

# ---------------------------------------------------------------------------
# Check 3 -- CLAUDE.md contains @AGENTIC.md import
# ---------------------------------------------------------------------------

if grep -qF '@AGENTIC.md' ~/.claude/CLAUDE.md 2>/dev/null; then
  check "CLAUDE.md contains @AGENTIC.md" "$PASS"
else
  check "CLAUDE.md contains @AGENTIC.md" "$FAIL"
fi

# ---------------------------------------------------------------------------
# Check 4 -- settings.json is valid JSON and contains both hook strings
# ---------------------------------------------------------------------------

if python3 -c "import json,sys; json.load(open(sys.argv[1]))" ~/.claude/settings.json 2>/dev/null; then
  check "settings.json is valid JSON" "$PASS"
else
  check "settings.json is valid JSON" "$FAIL"
fi

if grep -q 'session-scan.sh' ~/.claude/settings.json 2>/dev/null; then
  check "settings.json contains SessionStart hook ('session-scan.sh')" "$PASS"
else
  check "settings.json contains SessionStart hook ('session-scan.sh')" "$FAIL"
fi

if grep -q 'skill-review-nudge.sh' ~/.claude/settings.json 2>/dev/null; then
  check "settings.json contains SessionStart hook ('skill-review-nudge.sh')" "$PASS"
else
  check "settings.json contains SessionStart hook ('skill-review-nudge.sh')" "$FAIL"
fi

if grep -q 'pre-compact.sh' ~/.claude/settings.json 2>/dev/null; then
  check "settings.json contains PreCompact hook ('pre-compact.sh')" "$PASS"
else
  check "settings.json contains PreCompact hook ('pre-compact.sh')" "$FAIL"
fi

if grep -q 'stop-ledger-audit.sh' ~/.claude/settings.json 2>/dev/null; then
  check "settings.json contains Stop hook ('stop-ledger-audit.sh')" "$PASS"
else
  check "settings.json contains Stop hook ('stop-ledger-audit.sh')" "$FAIL"
fi

if grep -q 'orchestrator.sh' ~/.claude/settings.json 2>/dev/null; then
  check "settings.json contains UserPromptSubmit hook ('orchestrator.sh')" "$PASS"
else
  check "settings.json contains UserPromptSubmit hook ('orchestrator.sh')" "$FAIL"
fi

# ---------------------------------------------------------------------------
# Check 5 -- orchestrator hook short-prompt bypass + work-verb trigger
# ---------------------------------------------------------------------------

SHORT_OUT=$(echo '{"prompt":"hi"}' | bash ~/.claude/hooks/orchestrator.sh 2>/dev/null)
if [ -z "$SHORT_OUT" ]; then
  check "orchestrator hook: short prompt produces no output" "$PASS"
else
  check "orchestrator hook: short prompt produces no output" "$FAIL"
fi

LONG_OUT=$(echo '{"prompt":"please refactor the auth middleware and add retry logic"}' | bash ~/.claude/hooks/orchestrator.sh 2>/dev/null)
if echo "$LONG_OUT" | grep -q '^orchestrator:'; then
  check "orchestrator hook: work-verb prompt produces 'orchestrator:' output" "$PASS"
else
  check "orchestrator hook: work-verb prompt produces 'orchestrator:' output" "$FAIL"
fi

# ---------------------------------------------------------------------------
# Check 5b -- test-run advisor: fires on a foreground test or type-check run,
# skips background runs, subagents and other commands. The first case is the
# real command that ran three times in one session, once per cherry-pick batch.
# ---------------------------------------------------------------------------

TRA_STATE=$(mktemp -d)
tra() { AGENTIC_STATE_DIR="$TRA_STATE" bash "$SCRIPT_DIR/hooks/test-run-advisor.sh" 2>/dev/null; }
TRA_REAL=$(echo '{"session_id":"v1","tool_input":{"command":"cd apps/meteor && TZ=UTC npx jest client/lib/e2ee client/lib/e2eeSearch 2>&1 | grep Tests"}}' | tra)
TRA_AGAIN=$(echo '{"session_id":"v1","tool_input":{"command":"yarn test src/x"}}' | tra)
TRA_TSC=$(echo '{"session_id":"v2","tool_input":{"command":"npx tsc --noEmit --skipLibCheck"}}' | tra)
TRA_BG=$(echo '{"session_id":"v3","tool_input":{"command":"yarn test","run_in_background":true}}' | tra)
TRA_SUB=$(echo '{"session_id":"v4","agent_id":"a1","tool_input":{"command":"yarn test"}}' | tra)
TRA_OTHER=$(echo '{"session_id":"v5","tool_input":{"command":"ls jest.config.js"}}' | tra)
rm -rf "$TRA_STATE"
if echo "$TRA_REAL" | grep -q 'test-run:' && echo "$TRA_TSC" | grep -q 'test-run:'; then
  check "test-run advisor: foreground jest and tsc runs get advice" "$PASS"
else
  check "test-run advisor: foreground jest and tsc runs get advice" "$FAIL"
fi
if [ -z "$TRA_AGAIN$TRA_BG$TRA_SUB$TRA_OTHER" ]; then
  check "test-run advisor: rate limit, background, subagent and non-test commands stay silent" "$PASS"
else
  check "test-run advisor: rate limit, background, subagent and non-test commands stay silent" "$FAIL"
fi

# ---------------------------------------------------------------------------
# Check 6 -- session-scan.sh three-state test (exercises the real repo hook,
#            not a duplicated inline logic string)
# ---------------------------------------------------------------------------

# State A -- no .localdev/workflow dir
TMPDIR_A=$(mktemp -d)
STATE_A=$(cd "$TMPDIR_A" && echo '{"source":"startup"}' | bash "$SCRIPT_DIR/hooks/session-scan.sh" 2>/dev/null)
rm -rf "$TMPDIR_A"
if [ -z "$STATE_A" ]; then
  check "session-scan.sh state A (no .localdev/workflow): silent" "$PASS"
else
  check "session-scan.sh state A (no .localdev/workflow): silent" "$FAIL"
fi

# State B -- .localdev/workflow exists, nothing else -- digest is just "armed"
TMPDIR_B=$(mktemp -d)
mkdir -p "$TMPDIR_B/.localdev/workflow/handoffs"
STATE_B=$(cd "$TMPDIR_B" && echo '{"source":"startup"}' | bash "$SCRIPT_DIR/hooks/session-scan.sh" 2>/dev/null)
rm -rf "$TMPDIR_B"
if echo "$STATE_B" | grep -q 'agentic: armed'; then
  check "session-scan.sh state B (no blockers): prints 'armed'" "$PASS"
else
  check "session-scan.sh state B (no blockers): prints 'armed'" "$FAIL"
fi

# State C -- blockers.md has valid entry header
TMPDIR_C=$(mktemp -d)
mkdir -p "$TMPDIR_C/.localdev/workflow/handoffs"
echo '## 2026-04-16 14:00 -- test' > "$TMPDIR_C/.localdev/workflow/blockers.md"
STATE_C=$(cd "$TMPDIR_C" && echo '{"source":"startup"}' | bash "$SCRIPT_DIR/hooks/session-scan.sh" 2>/dev/null)
rm -rf "$TMPDIR_C"
if echo "$STATE_C" | grep -q 'Active blocker'; then
  check "session-scan.sh state C (active blocker): prints blocker warning" "$PASS"
else
  check "session-scan.sh state C (active blocker): prints blocker warning" "$FAIL"
fi

# ---------------------------------------------------------------------------
# Check 6b -- pre-compact.sh snapshot + session-scan.sh compaction-aware branch
# ---------------------------------------------------------------------------

TMPDIR_PC=$(mktemp -d)
mkdir -p "$TMPDIR_PC/.localdev/workflow"
cat > "$TMPDIR_PC/.localdev/workflow/todo.md" <<'EOF'
# Todo

## [doing] In-flight card
- Assignee: builder-fast
- Attempts: 1/2
- DoD: something
- Deps: none
EOF

(cd "$TMPDIR_PC" && echo '{"trigger":"auto"}' | bash "$SCRIPT_DIR/hooks/pre-compact.sh" >/dev/null 2>&1)
if [ -f "$TMPDIR_PC/.localdev/workflow/_precompact-snapshot.md" ]; then
  check "pre-compact.sh creates snapshot for an open [doing] card" "$PASS"
else
  check "pre-compact.sh creates snapshot for an open [doing] card" "$FAIL"
fi

COMPACT_OUT=$(cd "$TMPDIR_PC" && echo '{"source":"compact"}' | bash "$SCRIPT_DIR/hooks/session-scan.sh" 2>/dev/null)
if echo "$COMPACT_OUT" | grep -q 'compacted/resumed mid-session' && echo "$COMPACT_OUT" | python3 -m json.tool >/dev/null 2>&1; then
  check "session-scan.sh injects compaction warning first + valid JSON" "$PASS"
else
  check "session-scan.sh injects compaction warning first + valid JSON" "$FAIL"
fi
if [ -f "$TMPDIR_PC/.localdev/workflow/_precompact-snapshot.md" ]; then
  check "session-scan.sh removes snapshot after compact-source injection" "$FAIL"
else
  check "session-scan.sh removes snapshot after compact-source injection" "$PASS"
fi

(cd "$TMPDIR_PC" && echo '{"trigger":"auto"}' | bash "$SCRIPT_DIR/hooks/pre-compact.sh" >/dev/null 2>&1)
STARTUP_OUT=$(cd "$TMPDIR_PC" && echo '{"source":"startup"}' | bash "$SCRIPT_DIR/hooks/session-scan.sh" 2>/dev/null)
if echo "$STARTUP_OUT" | grep -q 'compacted/resumed mid-session'; then
  check "session-scan.sh does NOT inject compaction warning on startup" "$FAIL"
else
  check "session-scan.sh does NOT inject compaction warning on startup" "$PASS"
fi
if [ -f "$TMPDIR_PC/.localdev/workflow/_precompact-snapshot.md" ]; then
  check "session-scan.sh deletes stale snapshot on startup" "$FAIL"
else
  check "session-scan.sh deletes stale snapshot on startup" "$PASS"
fi

rm -rf "$TMPDIR_PC"

# ---------------------------------------------------------------------------
# Check 6c -- stop-ledger-audit.sh fixture (positive + negative + malformed)
# ---------------------------------------------------------------------------

TMPDIR_SA=$(mktemp -d)
mkdir -p "$TMPDIR_SA/.localdev/workflow"
mkdir -p "$TMPDIR_SA/repo/src"

# Positive fixture: [doing] card never touched, blockers/board mismatch,
# 3 non-ledger files written, done.md stale (predates the transcript).
cat > "$TMPDIR_SA/.localdev/workflow/todo.md" <<'EOF'
# Todo

## [doing] Some active card
- Assignee: builder-fast
- Attempts: 1/2
- DoD: something
- Deps: none
EOF
cat > "$TMPDIR_SA/.localdev/workflow/blockers.md" <<'EOF'
# Active Blockers

## 2026-08-01 10:00 -- some blocker summary
- Context: test
EOF
echo "# Done" > "$TMPDIR_SA/.localdev/workflow/done.md"
touch -t 202001010000 "$TMPDIR_SA/.localdev/workflow/done.md"

TRANSCRIPT="$TMPDIR_SA/transcript.jsonl"
cat > "$TRANSCRIPT" <<EOF
{"type":"user","timestamp":"2026-08-09T03:00:00.000Z","message":{"role":"user","content":"start"}}
{"type":"assistant","timestamp":"2026-08-09T03:01:00.000Z","message":{"role":"assistant","content":[{"type":"tool_use","name":"Write","input":{"file_path":"$TMPDIR_SA/repo/src/a.js","content":"a"}}]}}
{"type":"assistant","timestamp":"2026-08-09T03:02:00.000Z","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"$TMPDIR_SA/repo/src/b.js","old_string":"x","new_string":"y"}}]}}
{"type":"assistant","timestamp":"2026-08-09T03:03:00.000Z","message":{"role":"assistant","content":[{"type":"tool_use","name":"Write","input":{"file_path":"$TMPDIR_SA/repo/src/c.js","content":"c"}}]}}
EOF

STOP_JSON=$(python3 -c "import json,sys; print(json.dumps({'transcript_path': sys.argv[1], 'stop_hook_active': False}))" "$TRANSCRIPT")
STOP_OUT=$(cd "$TMPDIR_SA" && echo "$STOP_JSON" | bash "$SCRIPT_DIR/hooks/stop-ledger-audit.sh" 2>/dev/null)

AUDIT_FILE="$TMPDIR_SA/.localdev/workflow/_audit-pending.md"
if [ -f "$AUDIT_FILE" ] \
   && grep -q 'files changed but done.md' "$AUDIT_FILE" \
   && grep -q 'left \[doing\]' "$AUDIT_FILE" \
   && grep -q 'blockers.md has entries' "$AUDIT_FILE"; then
  check "stop-ledger-audit.sh positive fixture: all 3 checks fire in _audit-pending.md" "$PASS"
else
  check "stop-ledger-audit.sh positive fixture: all 3 checks fire in _audit-pending.md" "$FAIL"
fi

if [ -n "$STOP_OUT" ] && echo "$STOP_OUT" | python3 -m json.tool >/dev/null 2>&1; then
  check "stop-ledger-audit.sh positive fixture: stdout is valid JSON" "$PASS"
else
  check "stop-ledger-audit.sh positive fixture: stdout is valid JSON" "$FAIL"
fi

# Negative fixture: fresh done.md, no [doing] cards, consistent (empty) blockers.
rm -f "$AUDIT_FILE"
cat > "$TMPDIR_SA/.localdev/workflow/todo.md" <<'EOF'
# Todo
EOF
: > "$TMPDIR_SA/.localdev/workflow/blockers.md"
echo "# Done" > "$TMPDIR_SA/.localdev/workflow/done.md"
# Force a fixed future mtime (not "now") so this check isn't time-of-day
# flaky relative to the transcript's fixed 2026-08-09T03:00 timestamp.
touch -t 209912310000 "$TMPDIR_SA/.localdev/workflow/done.md"

NEG_OUT=$(cd "$TMPDIR_SA" && echo "$STOP_JSON" | bash "$SCRIPT_DIR/hooks/stop-ledger-audit.sh" 2>/dev/null)
NEG_EXIT=$?
if [ ! -f "$AUDIT_FILE" ] && [ -z "$NEG_OUT" ] && [ "$NEG_EXIT" -eq 0 ]; then
  check "stop-ledger-audit.sh negative fixture: no audit file, no output, exit 0" "$PASS"
else
  check "stop-ledger-audit.sh negative fixture: no audit file, no output, exit 0" "$FAIL"
fi

# Malformed stdin / missing transcript_path / garbage transcript -- exit 0 silently.
MALFORMED_OUT=$(cd "$TMPDIR_SA" && echo 'not json' | bash "$SCRIPT_DIR/hooks/stop-ledger-audit.sh" 2>/dev/null)
MALFORMED_EXIT=$?
NOTRANSCRIPT_OUT=$(cd "$TMPDIR_SA" && echo '{}' | bash "$SCRIPT_DIR/hooks/stop-ledger-audit.sh" 2>/dev/null)
NOTRANSCRIPT_EXIT=$?
GARBAGE="$TMPDIR_SA/garbage.jsonl"
printf 'not json\nalso not json\n{"partial":' > "$GARBAGE"
GARBAGE_JSON=$(python3 -c "import json,sys; print(json.dumps({'transcript_path': sys.argv[1]}))" "$GARBAGE")
GARBAGE_OUT=$(cd "$TMPDIR_SA" && echo "$GARBAGE_JSON" | bash "$SCRIPT_DIR/hooks/stop-ledger-audit.sh" 2>/dev/null)
GARBAGE_EXIT=$?
if [ "$MALFORMED_EXIT" -eq 0 ] && [ -z "$MALFORMED_OUT" ] \
   && [ "$NOTRANSCRIPT_EXIT" -eq 0 ] && [ -z "$NOTRANSCRIPT_OUT" ] \
   && [ "$GARBAGE_EXIT" -eq 0 ] && [ -z "$GARBAGE_OUT" ]; then
  check "stop-ledger-audit.sh: malformed stdin / missing transcript_path / garbage transcript all exit 0 silently" "$PASS"
else
  check "stop-ledger-audit.sh: malformed stdin / missing transcript_path / garbage transcript all exit 0 silently" "$FAIL"
fi

rm -rf "$TMPDIR_SA"

# ---------------------------------------------------------------------------
# Check 6d -- ledger-append.sh concurrency + error-path fixture
# ---------------------------------------------------------------------------

TMPDIR_LA=$(mktemp -d)
mkdir -p "$TMPDIR_LA/.localdev/workflow"
(
  cd "$TMPDIR_LA" || exit 1
  LA_TARGET="done"
  for i in $(seq 20); do
    printf '## entry %s\nline2-%s\nline3-%s\n' "$i" "$i" "$i" \
      | bash "$SCRIPT_DIR/scripts/ledger-append.sh" "$LA_TARGET" &
  done
  wait
)

LA_CHECK=$(python3 - "$TMPDIR_LA/.localdev/workflow/done.md" <<'PYEOF'
import re
import sys

path = sys.argv[1]
try:
    with open(path) as fh:
        text = fh.read()
except Exception:
    print("FAIL: could not read done.md")
    sys.exit(0)

headers = re.findall(r"^## entry (\d+)$", text, re.MULTILINE)
if len(headers) != 20:
    print(f"FAIL: expected 20 '## entry' headers, found {len(headers)}")
    sys.exit(0)
if sorted(int(h) for h in headers) != list(range(1, 21)):
    print("FAIL: entry numbers are not exactly 1..20")
    sys.exit(0)

lines = text.split("\n")
ok = True
for idx, line in enumerate(lines):
    m = re.match(r"^## entry (\d+)$", line)
    if not m:
        continue
    n = m.group(1)
    expected = [f"## entry {n}", f"line2-{n}", f"line3-{n}"]
    actual = lines[idx:idx + 3]
    if actual != expected:
        ok = False
        print(f"FAIL: entry {n} lines not contiguous/in-order: {actual!r} != {expected!r}")
        break
if ok:
    print("PASS: all 20 entries contiguous, in order, un-interleaved")
PYEOF
)

if echo "$LA_CHECK" | grep -q '^PASS'; then
  check "ledger-append.sh concurrency: 20 parallel appends, all intact and un-interleaved" "$PASS"
else
  check "ledger-append.sh concurrency: 20 parallel appends, all intact and un-interleaved" "$FAIL"
fi

if [ -d "$TMPDIR_LA/.localdev/workflow/.done.md.lock" ]; then
  check "ledger-append.sh concurrency: lock dir removed after run" "$FAIL"
else
  check "ledger-append.sh concurrency: lock dir removed after run" "$PASS"
fi

# A lock dir left by a crashed writer (2020 mtime) must be swept at once on
# both GNU and BSD stat. On Linux, `stat -f` is filesystem status and once
# broke the age arithmetic, so the writer died and the entry was lost.
TMPDIR_STALE=$(mktemp -d)
mkdir -p "$TMPDIR_STALE/.localdev/workflow/.done.md.lock"
touch -t 202001010000 "$TMPDIR_STALE/.localdev/workflow/.done.md.lock"
(cd "$TMPDIR_STALE" && printf '## stale-entry\n' | bash "$SCRIPT_DIR/scripts/ledger-append.sh" "done" 2>/dev/null)
if grep -q '^## stale-entry$' "$TMPDIR_STALE/.localdev/workflow/done.md" 2>/dev/null \
   && ! grep -q 'lock-timeout' "$TMPDIR_STALE/.localdev/workflow/done.md" \
   && [ ! -d "$TMPDIR_STALE/.localdev/workflow/.done.md.lock" ]; then
  check "ledger-append.sh: stale lock swept at once, entry appended without timeout" "$PASS"
else
  check "ledger-append.sh: stale lock swept at once, entry appended without timeout" "$FAIL"
fi
rm -rf "$TMPDIR_STALE"

(cd "$TMPDIR_LA" && echo hi | bash "$SCRIPT_DIR/scripts/ledger-append.sh" bogus >/dev/null 2>/tmp/ledger_err_$$.txt)
LA_BOGUS_EXIT=$?
if [ "$LA_BOGUS_EXIT" -ne 0 ] && [ -s "/tmp/ledger_err_$$.txt" ]; then
  check "ledger-append.sh: unknown target exits nonzero with stderr" "$PASS"
else
  check "ledger-append.sh: unknown target exits nonzero with stderr" "$FAIL"
fi
rm -f "/tmp/ledger_err_$$.txt"

TMPDIR_LA_NOWF=$(mktemp -d)
(cd "$TMPDIR_LA_NOWF" && LA_TARGET="done" && echo hi | bash "$SCRIPT_DIR/scripts/ledger-append.sh" "$LA_TARGET" >/dev/null 2>/tmp/ledger_err2_$$.txt)
LA_NOWF_EXIT=$?
if [ "$LA_NOWF_EXIT" -ne 0 ] && [ -s "/tmp/ledger_err2_$$.txt" ]; then
  check "ledger-append.sh: missing .localdev/workflow/ exits nonzero with stderr" "$PASS"
else
  check "ledger-append.sh: missing .localdev/workflow/ exits nonzero with stderr" "$FAIL"
fi
rm -f "/tmp/ledger_err2_$$.txt"
rm -rf "$TMPDIR_LA_NOWF"

rm -rf "$TMPDIR_LA"

# ---------------------------------------------------------------------------
# Check 6e -- blocker defaults + standing orders in session-scan.sh
# ---------------------------------------------------------------------------

TMPDIR_SS=$(mktemp -d)
mkdir -p "$TMPDIR_SS/.localdev/workflow"
cat > "$TMPDIR_SS/.localdev/workflow/blockers.md" <<'EOF'
# Active Blockers

## 2026-10-05 10:00 -- pick the cache backend
- Context: test
- What I need: redis or sqlite
- Default if no answer: use sqlite behind the CacheStore interface
- Files involved: src/cache.ts
EOF
cat > "$TMPDIR_SS/.localdev/workflow/standing.md" <<'EOF'
1. Never push without asking.
2. Run the focused spec, not the full suite.
EOF
cat > "$TMPDIR_SS/.localdev/workflow/todo.md" <<'EOF'
# Todo

## [blocked] Cache backend
- Attempts: 0/2
EOF
(cd "$TMPDIR_SS" && echo '{"trigger":"auto"}' | bash "$SCRIPT_DIR/hooks/pre-compact.sh" >/dev/null 2>&1)
SS_OUT=$(cd "$TMPDIR_SS" && echo '{"source":"compact"}' | bash "$SCRIPT_DIR/hooks/session-scan.sh" 2>/dev/null)
SS_CHECK=$(printf '%s' "$SS_OUT" | python3 -c '
import json, sys
ctx = json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"]
lines = ctx.split("\n")
want = "1. Never push without asking.\n2. Run the focused spec, not the full suite."
bi = next(i for i, l in enumerate(lines) if "Active blocker: 2026-10-05 10:00" in l)
ok_default = lines[bi + 1] == "   Default if no answer: use sqlite behind the CacheStore interface"
ok_standing = want in ctx
ok_order = 0 <= ctx.find("compacted/resumed") < ctx.find(want) < ctx.find("Active blocker")
print("PASS" if ok_default else "FAIL-default", "PASS" if ok_standing and ok_order else "FAIL-standing")
' 2>/dev/null)
if [ "${SS_CHECK%% *}" = "PASS" ]; then
  check "session-scan.sh prints each blocker's 'Default if no answer' under its title" "$PASS"
else
  check "session-scan.sh prints each blocker's 'Default if no answer' under its title" "$FAIL"
fi
if [ "${SS_CHECK##* }" = "PASS" ]; then
  check "session-scan.sh injects standing.md verbatim, after the compaction notice (source=compact)" "$PASS"
else
  check "session-scan.sh injects standing.md verbatim, after the compaction notice (source=compact)" "$FAIL"
fi
rm -rf "$TMPDIR_SS"

# ---------------------------------------------------------------------------
# Check 6f -- stop-ledger-audit.sh Verified-sha and decision-log checks
# ---------------------------------------------------------------------------

TMPDIR_VS=$(mktemp -d)
mkdir -p "$TMPDIR_VS/.localdev/workflow"
(cd "$TMPDIR_VS" && git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init) >/dev/null 2>&1
VS_HEAD=$(cd "$TMPDIR_VS" && git rev-parse --short HEAD 2>/dev/null)
cat > "$TMPDIR_VS/.localdev/workflow/todo.md" <<'EOF'
# Todo

## [todo] Stale card
- Tier: full
- Verified: test @ 0000000
EOF
echo "# Done" > "$TMPDIR_VS/.localdev/workflow/done.md"
VS_TRANSCRIPT="$TMPDIR_VS/transcript.jsonl"
echo '{"type":"user","timestamp":"2026-08-09T03:00:00.000Z","message":{"role":"user","content":"start"}}' > "$VS_TRANSCRIPT"
VS_JSON=$(python3 -c "import json,sys; print(json.dumps({'transcript_path': sys.argv[1], 'session_id': 's1'}))" "$VS_TRANSCRIPT")
VS_OUT1=$(cd "$TMPDIR_VS" && echo "$VS_JSON" | bash "$SCRIPT_DIR/hooks/stop-ledger-audit.sh" 2>/dev/null)
VS_OUT2=$(cd "$TMPDIR_VS" && echo "$VS_JSON" | bash "$SCRIPT_DIR/hooks/stop-ledger-audit.sh" 2>/dev/null)
if [ -n "$VS_HEAD" ] && echo "$VS_OUT1" | grep -q "verified at 0000000, HEAD is $VS_HEAD" \
   && echo "$VS_OUT1" | grep -q 'has no decisions.tsv row this session' \
   && echo "$VS_OUT1" | python3 -m json.tool >/dev/null 2>&1; then
  check "stop-ledger-audit.sh: stale Verified sha and missing full-tier decision row both warn" "$PASS"
else
  check "stop-ledger-audit.sh: stale Verified sha and missing full-tier decision row both warn" "$FAIL"
fi
if [ -z "$VS_OUT2" ]; then
  check "stop-ledger-audit.sh: same session, same warnings -> rate-limited (silent)" "$PASS"
else
  check "stop-ledger-audit.sh: same session, same warnings -> rate-limited (silent)" "$FAIL"
fi
VS_AGENT=$(python3 -c "import json,sys; print(json.dumps({'transcript_path': sys.argv[1], 'session_id': 's2', 'agent_id': 'a1'}))" "$VS_TRANSCRIPT")
VS_OUT3=$(cd "$TMPDIR_VS" && echo "$VS_AGENT" | bash "$SCRIPT_DIR/hooks/stop-ledger-audit.sh" 2>/dev/null)
if [ -z "$VS_OUT3" ]; then
  check "stop-ledger-audit.sh: subagent payload (agent_id) is skipped" "$PASS"
else
  check "stop-ledger-audit.sh: subagent payload (agent_id) is skipped" "$FAIL"
fi
sed -i.bak "s/@ 0000000/@ $VS_HEAD/" "$TMPDIR_VS/.localdev/workflow/todo.md"
(cd "$TMPDIR_VS" && bash "$SCRIPT_DIR/scripts/ledger-append.sh" decision build "chose X" "faster" "abc123" "tests green")
VS_JSON3=$(python3 -c "import json,sys; print(json.dumps({'transcript_path': sys.argv[1], 'session_id': 's3'}))" "$VS_TRANSCRIPT")
VS_OUT4=$(cd "$TMPDIR_VS" && echo "$VS_JSON3" | bash "$SCRIPT_DIR/hooks/stop-ledger-audit.sh" 2>/dev/null)
if [ -z "$VS_OUT4" ]; then
  check "stop-ledger-audit.sh: Verified @ HEAD + decision row this session -> silent" "$PASS"
else
  check "stop-ledger-audit.sh: Verified @ HEAD + decision row this session -> silent" "$FAIL"
fi
rm -rf "$TMPDIR_VS"

# ---------------------------------------------------------------------------
# Check 6g -- ledger-append.sh decision target (header, sanitize, usage)
# ---------------------------------------------------------------------------

TMPDIR_DL=$(mktemp -d)
mkdir -p "$TMPDIR_DL/.localdev/workflow"
(
  cd "$TMPDIR_DL" || exit 1
  bash "$SCRIPT_DIR/scripts/ledger-append.sh" decision frame "split	the
card" "=cmd()" "-1" "@here" >/dev/null 2>&1
  bash "$SCRIPT_DIR/scripts/ledger-append.sh" decision build "kept default" "reversible" "+abc" "open" >/dev/null 2>&1
)
DL_CHECK=$(python3 - "$TMPDIR_DL/.localdev/workflow/decisions.tsv" <<'PYEOF'
import re, sys
rows = open(sys.argv[1]).read().split("\n")
ok = (
    rows[0] == "ts\tphase\tdecision\twhy\tevidence\tresult"
    and len(rows) == 4 and rows[3] == ""
    and all(len(r.split("\t")) == 6 for r in rows[1:3])
    and re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", rows[1].split("\t")[0])
    and rows[1].split("\t")[1:] == ["frame", "split the card", "'=cmd()", "'-1", "'@here"]
    and rows[2].split("\t")[4] == "'+abc"
)
print("PASS" if ok else "FAIL")
PYEOF
)
if [ "$DL_CHECK" = "PASS" ]; then
  check "ledger-append.sh decision: header once, 6 cells, tabs/newlines stripped, = + - @ escaped" "$PASS"
else
  check "ledger-append.sh decision: header once, 6 cells, tabs/newlines stripped, = + - @ escaped" "$FAIL"
fi
(cd "$TMPDIR_DL" && bash "$SCRIPT_DIR/scripts/ledger-append.sh" decision too few >/dev/null 2>"$TMPDIR_DL/err.txt")
DL_USAGE_EXIT=$?
if [ "$DL_USAGE_EXIT" -ne 0 ] && [ -s "$TMPDIR_DL/err.txt" ]; then
  check "ledger-append.sh decision: wrong arg count exits nonzero with usage on stderr" "$PASS"
else
  check "ledger-append.sh decision: wrong arg count exits nonzero with usage on stderr" "$FAIL"
fi
rm -rf "$TMPDIR_DL"

# ---------------------------------------------------------------------------
# Check 7 -- repo structural integrity (ported from Codex validate.mjs)
# Validates the source repo at $SCRIPT_DIR, not the ~/.claude/ install.
# ---------------------------------------------------------------------------

# 7a -- .claude-plugin/plugin.json exists and is valid JSON
PLUGIN_JSON="$SCRIPT_DIR/.claude-plugin/plugin.json"
if [ -f "$PLUGIN_JSON" ] && python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$PLUGIN_JSON" 2>/dev/null; then
  check ".claude-plugin/plugin.json exists and is valid JSON" "$PASS"
else
  check ".claude-plugin/plugin.json exists and is valid JSON" "$FAIL"
fi

# 7b -- agent files exist in agents/ (count derived from repo contents, not
#       hardcoded, so new agents don't require an installer/verify edit)
AGENT_FILES=("$SCRIPT_DIR"/agents/*.md)
if [ "${#AGENT_FILES[@]}" -gt 0 ]; then
  check "all ${#AGENT_FILES[@]} agent files exist in agents/" "$PASS"
else
  check "agent files exist in agents/" "$FAIL"
fi

# 7c -- command files exist in commands/ (count derived from repo contents)
COMMAND_FILES=("$SCRIPT_DIR"/commands/*.md)
if [ "${#COMMAND_FILES[@]}" -gt 0 ]; then
  check "all ${#COMMAND_FILES[@]} command files exist in commands/" "$PASS"
else
  check "command files exist in commands/" "$FAIL"
fi

# 7d -- every repo skill has a SKILL.md with valid frontmatter (--- ... description:)
for skill_dir in "$SCRIPT_DIR/skills"/*/; do
  [ -d "$skill_dir" ] || continue
  s="$(basename "$skill_dir")"
  SKILL_FILE="$skill_dir/SKILL.md"
  if [ -f "$SKILL_FILE" ] \
     && head -n 1 "$SKILL_FILE" | grep -qx -- '---' \
     && grep -q '^description:' "$SKILL_FILE"; then
    check "skill exists with frontmatter: skills/$s/SKILL.md" "$PASS"
  else
    check "skill exists with frontmatter: skills/$s/SKILL.md" "$FAIL"
  fi
done

# 7d-guard -- a vacuous loop must not read as success. If skills/*/ matched
#             nothing, the loop above emitted zero checks and the suite would
#             pass having verified nothing.
SKILL_N=0
for skill_dir in "$SCRIPT_DIR/skills"/*/; do
  [ -d "$skill_dir" ] && SKILL_N=$((SKILL_N + 1))
done
if [ "$SKILL_N" -gt 0 ]; then
  check "repo contains at least one skill ($SKILL_N found)" "$PASS"
else
  check "repo contains at least one skill" "$FAIL"
fi

# 7e -- repo hook scripts exist and pass bash syntax check
for h in orchestrator.sh inject-agentic-context.sh allow-workflow-paths.sh session-scan.sh pre-compact.sh stop-ledger-audit.sh; do
  if [ -f "$SCRIPT_DIR/hooks/$h" ] && bash -n "$SCRIPT_DIR/hooks/$h" 2>/dev/null; then
    check "hooks/$h exists in repo and parses" "$PASS"
  else
    check "hooks/$h exists in repo and parses" "$FAIL"
  fi
done

if [ -f "$SCRIPT_DIR/scripts/ledger-append.sh" ] && bash -n "$SCRIPT_DIR/scripts/ledger-append.sh" 2>/dev/null; then
  check "scripts/ledger-append.sh exists in repo and parses" "$PASS"
else
  check "scripts/ledger-append.sh exists in repo and parses" "$FAIL"
fi

# ---------------------------------------------------------------------------
# Check 8 -- every repo skill is installed in ~/.claude/skills/
#            (list derived from repo contents)
# ---------------------------------------------------------------------------

for skill_dir in "$SCRIPT_DIR/skills"/*/; do
  [ -d "$skill_dir" ] || continue
  s="$(basename "$skill_dir")"
  if test -f ~/.claude/skills/"$s"/SKILL.md; then
    check "~/.claude/skills/$s/SKILL.md exists" "$PASS"
  else
    check "~/.claude/skills/$s/SKILL.md exists" "$FAIL"
  fi
done

# ---------------------------------------------------------------------------
# Check 8b -- every relative doc link in the INSTALLED AGENTIC.md resolves to a
#             real file under ~/.claude/. The doctrine loads its detail on
#             demand, so a link that dangles at runtime silently removes that
#             guidance with nothing else catching it. Parsed from the file, so
#             it tracks whatever the doctrine currently links to. Zero links is
#             a failure, not a pass -- that is the vacuous case.
# ---------------------------------------------------------------------------

if python3 - ~/.claude/AGENTIC.md <<'PYEOF'
import os, re, sys
path = os.path.expanduser(sys.argv[1])
if not os.path.isfile(path):
    sys.exit(1)
base = os.path.dirname(path)
links = re.findall(r"\]\(([^)]+\.md)\)", open(path).read())
rel = [l for l in links if not l.startswith(("http://", "https://"))]
missing = [l for l in rel if not os.path.isfile(os.path.join(base, l))]
if missing:
    print("dangling: " + ", ".join(missing), file=sys.stderr)
sys.exit(1 if (missing or not rel) else 0)
PYEOF
then
  check "installed AGENTIC.md: every relative doc link resolves under ~/.claude/" "$PASS"
else
  check "installed AGENTIC.md: every relative doc link resolves under ~/.claude/" "$FAIL"
fi

# ---------------------------------------------------------------------------
# Check 9 -- settings.json permissions.allow contains framework globs and
#            does NOT contain any stale .claude/mytasks glob
# ---------------------------------------------------------------------------

if python3 - ~/.claude/settings.json <<'PYEOF'
import json, sys, os
path = sys.argv[1]
if not os.path.isfile(path):
    sys.exit(1)
data = json.load(open(path))
allow = data.get("permissions", {}).get("allow", [])
REQUIRED = [
    "Edit(.localdev/workflow/**)",
    "Edit(.localdev/workflow/handoffs/**)",
    "Edit(docs/KNOWN_ISSUES.md)",
]
missing = [g for g in REQUIRED if g not in allow]
sys.exit(1 if missing else 0)
PYEOF
then
  check "settings.json permissions.allow contains the 3 framework Edit globs" "$PASS"
else
  check "settings.json permissions.allow contains the 3 framework Edit globs" "$FAIL"
fi

# Claude Code matches file permissions only against Edit(path) rules and
# warns at startup about every Write(path) rule, so none may remain.
if python3 - ~/.claude/settings.json <<'PYEOF'
import json, sys, os
path = sys.argv[1]
if not os.path.isfile(path):
    sys.exit(0)
data = json.load(open(path))
allow = data.get("permissions", {}).get("allow", [])
dead = [g for g in allow if g.startswith("Write(") and g != "Write"]
if dead:
    print("dead Write(path) rules (use Edit(path)): " + ", ".join(dead), file=sys.stderr)
sys.exit(1 if dead else 0)
PYEOF
then
  check "settings.json permissions.allow contains NO Write(path) rules" "$PASS"
else
  check "settings.json permissions.allow contains NO Write(path) rules" "$FAIL"
fi

if python3 - ~/.claude/settings.json <<'PYEOF'
import json, sys, os
path = sys.argv[1]
if not os.path.isfile(path):
    sys.exit(0)
data = json.load(open(path))
allow = data.get("permissions", {}).get("allow", [])
stale = [g for g in allow if '.claude/mytasks' in g]
sys.exit(1 if stale else 0)
PYEOF
then
  check "settings.json permissions.allow contains NO stale .claude/mytasks globs" "$PASS"
else
  check "settings.json permissions.allow contains NO stale .claude/mytasks globs" "$FAIL"
fi

# ---------------------------------------------------------------------------
# Check 10 -- role/agent parity between agents/*.md and the delegation
#             reference's role table, in both directions. The doctrine no
#             longer pins model aliases (each role carries its own frontmatter
#             `model:`), so there is nothing to cross-check there; what can
#             still drift is a role documented with no definition, or a
#             definition absent from the table. Parsed fresh at runtime.
# ---------------------------------------------------------------------------

ROLE_REF="$SCRIPT_DIR/skills/agentic-workflow/references/delegation.md"

if [ ! -f "$ROLE_REF" ]; then
  check "delegation reference present (role table source)" "$FAIL"
else
  AGENT_N=0
  for agent_src in "$SCRIPT_DIR"/agents/*.md; do
    AGENT_N=$((AGENT_N + 1))
    agent_name="$(basename "$agent_src" .md)"
    if grep -qE "^\| *${agent_name} *\|" "$ROLE_REF"; then
      check "role documented in delegation reference: $agent_name" "$PASS"
    else
      check "role documented in delegation reference: $agent_name" "$FAIL"
    fi
  done

  if [ "$AGENT_N" -gt 0 ]; then
    check "repo contains at least one agent definition ($AGENT_N found)" "$PASS"
  else
    check "repo contains at least one agent definition" "$FAIL"
  fi

  ROLE_ROWS="$(mktemp)"
  grep -oE '^\| *[a-z][a-z-]* *\|' "$ROLE_REF" | tr -d '| ' > "$ROLE_ROWS"
  while IFS= read -r role; do
    [ -n "$role" ] || continue
    if [ -f "$SCRIPT_DIR/agents/$role.md" ]; then
      check "role table row has an agent definition: $role" "$PASS"
    else
      check "role table row has an agent definition: $role" "$FAIL"
    fi
  done < "$ROLE_ROWS"
  rm -f "$ROLE_ROWS"
fi

# ---------------------------------------------------------------------------
# Check 11 -- skill-review script on a synthetic Claude home: counts a real
#            Skill call, ignores a name that is only mentioned, flags a
#            session that saved a lesson with no wiki page, flags a session
#            that searched old transcripts with no transcript skill (missed
#            skill), and runs the nudge states (no wiki set, report ready,
#            reviewed).
# ---------------------------------------------------------------------------

SR="$SCRIPT_DIR/skills/skill-review/scripts/skill_review.py"
SR_HOME=$(mktemp -d)
mkdir -p "$SR_HOME/projects/p" "$SR_HOME/skills/used-skill" "$SR_HOME/skills/idle-skill" "$SR_HOME/wiki"
printf -- '---\nname: used-skill\ndescription: x\n---\n' > "$SR_HOME/skills/used-skill/SKILL.md"
printf -- '---\nname: idle-skill\ndescription: x\n---\n' > "$SR_HOME/skills/idle-skill/SKILL.md"
SR_TS=$(python3 -c "from datetime import datetime,timezone;print(datetime.now(timezone.utc).isoformat())")
cat > "$SR_HOME/projects/p/s1.jsonl" <<JSONL
{"type":"user","timestamp":"$SR_TS","cwd":"/tmp","message":{"role":"user","content":"mention idle-skill only"}}
{"type":"assistant","timestamp":"$SR_TS","message":{"role":"assistant","content":[{"type":"tool_use","name":"Skill","input":{"skill":"used-skill"}},{"type":"tool_use","name":"Write","input":{"file_path":"$SR_HOME/projects/p/memory/new-finding.md"}}]}}
JSONL
cat > "$SR_HOME/projects/p/s2.jsonl" <<JSONL
{"type":"user","timestamp":"$SR_TS","cwd":"/tmp","message":{"role":"user","content":"clean the disk again"}}
{"type":"assistant","timestamp":"$SR_TS","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"grep -l 'clean the disk' ~/.claude/projects/*/*.jsonl"}}]}}
JSONL
cat > "$SR_HOME/projects/p/s3.jsonl" <<JSONL
{"type":"user","timestamp":"$SR_TS","cwd":"/tmp","message":{"role":"user","content":"mine the sessions"}}
{"type":"assistant","timestamp":"$SR_TS","message":{"role":"assistant","content":[{"type":"tool_use","name":"Skill","input":{"skill":"session-mining"}},{"type":"tool_use","name":"Bash","input":{"command":"grep -l x ~/.claude/projects/*/*.jsonl"}}]}}
JSONL

SR_NUDGE_A=$(CLAUDE_CONFIG_DIR="$SR_HOME" python3 "$SR" nudge 2>/dev/null)
if echo "$SR_NUDGE_A" | grep -q 'no wiki folder is set'; then
  check "skill-review nudge: asks for a wiki folder when none is set" "$PASS"
else
  check "skill-review nudge: asks for a wiki folder when none is set" "$FAIL"
fi

CLAUDE_CONFIG_DIR="$SR_HOME" python3 "$SR" config --wiki-dir "$SR_HOME/wiki" >/dev/null 2>&1
CLAUDE_CONFIG_DIR="$SR_HOME" python3 "$SR" measure >/dev/null 2>&1
SR_RESULT=$(python3 - "$SR_HOME" <<'PYEOF'
import glob, json, sys
r = json.load(open(sorted(glob.glob(sys.argv[1] + "/agentic-state/skill-review/report-*.json"))[-1]))
uses = {s["key"]: s["uses_long"] for s in r["skills"]}
ok = (uses.get("used-skill") == 1 and uses.get("idle-skill") == 0
      and r["wiki"]["missed_count"] == 1 and r["missed_skill_count"] == 1)
print("ok" if ok else f"bad {uses} missed={r['wiki']['missed_count']} missed_skills={r['missed_skill_count']}")
PYEOF
)
if [ "$SR_RESULT" = "ok" ] && ls "$SR_HOME/wiki/Skill Reviews/"*"Skill Review.md" >/dev/null 2>&1; then
  check "skill-review measure: counts invoked only, flags missed wiki and missed skill, writes wiki report" "$PASS"
else
  check "skill-review measure: counts invoked only, flags missed wiki and missed skill, writes wiki report ($SR_RESULT)" "$FAIL"
fi

SR_NUDGE_B=$(CLAUDE_CONFIG_DIR="$SR_HOME" python3 "$SR" nudge 2>/dev/null)
CLAUDE_CONFIG_DIR="$SR_HOME" python3 "$SR" reviewed >/dev/null 2>&1
rm -f "$SR_HOME/agentic-state/skill-review/nudged-review"
SR_NUDGE_C=$(CLAUDE_CONFIG_DIR="$SR_HOME" python3 "$SR" nudge 2>/dev/null)
if echo "$SR_NUDGE_B" | grep -q 'report is ready' && [ -z "$SR_NUDGE_C" ]; then
  check "skill-review nudge: points to a new report, silent after review" "$PASS"
else
  check "skill-review nudge: points to a new report, silent after review" "$FAIL"
fi
rm -rf "$SR_HOME"

# ---------------------------------------------------------------------------
# Check -- role-spend prices Haiku 5.5 on its two rate cards. Two turns:
#   50K-token prompt at $0.10/MTok = $0.005, 150K-token prompt at $0.50/MTok
#   = $0.075. Total $0.08. One card for both turns would print $0.02.
# ---------------------------------------------------------------------------

RS_HOME=$(mktemp -d)
RS_DIR="$RS_HOME/projects/p/s/subagents"
mkdir -p "$RS_DIR"
echo '{"agentType":"finder"}' > "$RS_DIR/agent-x.meta.json"
python3 - "$RS_DIR/agent-x.jsonl" <<'PYEOF'
import json, sys
with open(sys.argv[1], 'w') as f:
    for i, n in enumerate((50_000, 150_000)):
        f.write(json.dumps({'type': 'assistant', 'message': {'id': f'm{i}', 'model': 'claude-haiku-5-5',
                            'usage': {'input_tokens': n, 'output_tokens': 0}}}) + '\n')
PYEOF
RS_OUT=$(CLAUDE_CONFIG_DIR="$RS_HOME" python3 "$SCRIPT_DIR/scripts/role-spend.py" --days 1 2>&1)
if echo "$RS_OUT" | grep -qF "est. \$0.08 " && echo "$RS_OUT" | grep -q '^finder '; then
  check "role-spend: prices Haiku 5.5 on both rate cards" "$PASS"
else
  check "role-spend: prices Haiku 5.5 on both rate cards (got: $(echo "$RS_OUT" | head -1))" "$FAIL"
fi
rm -rf "$RS_HOME"

# ---------------------------------------------------------------------------
# Check -- role-spend counts the main session and lists the top runs. A main
#   session turn with 100K Opus output tokens costs $2.00, a reviewer turn with
#   50K costs $1.00. Total $3.00. A report of subagents only would print $1.00.
# ---------------------------------------------------------------------------

RS_HOME=$(mktemp -d)
mkdir -p "$RS_HOME/projects/p/s/subagents"
echo '{"agentType":"reviewer","description":"probe review"}' > "$RS_HOME/projects/p/s/subagents/agent-y.meta.json"
python3 - "$RS_HOME/projects/p" <<'PYEOF'
import json, os, sys
for path, n in ((os.path.join(sys.argv[1], 's.jsonl'), 100_000),
                (os.path.join(sys.argv[1], 's/subagents/agent-y.jsonl'), 50_000)):
    with open(path, 'w') as f:
        f.write(json.dumps({'type': 'assistant', 'message': {'id': 'm', 'model': 'claude-opus-5-5',
                            'usage': {'input_tokens': 0, 'output_tokens': n}}}) + '\n')
PYEOF
RS_OUT=$(CLAUDE_CONFIG_DIR="$RS_HOME" python3 "$SCRIPT_DIR/scripts/role-spend.py" --days 1 --top 2 2>&1)
if echo "$RS_OUT" | grep -qF "est. \$3.00 " && echo "$RS_OUT" | grep -q '^(main session) ' \
   && echo "$RS_OUT" | grep -qE '^ +1\.00  reviewer .*probe review$'; then
  check "role-spend: counts the main session and lists the top runs" "$PASS"
else
  check "role-spend: counts the main session and lists the top runs (got: $(echo "$RS_OUT" | head -1))" "$FAIL"
fi
rm -rf "$RS_HOME"

# ---------------------------------------------------------------------------
# Check -- role-ab check accepts a valid spec and rejects a bad base commit
#   before any arm spends money.
# ---------------------------------------------------------------------------

RA_DIR=$(mktemp -d)
touch "$RA_DIR/brief.md" "$RA_DIR/grade.py"
ra_spec() {
  printf '{"out":"%s/out","agent":"builder-fast","arms":[{"id":"a","model":"haiku","effort":"low"}],"tasks":[{"id":"t","repo":"%s","base":"%s","brief":"brief.md","grade":"grade.py"}]}' \
    "$RA_DIR" "$SCRIPT_DIR" "$1"
}
ra_spec HEAD > "$RA_DIR/good.json"
ra_spec 0000000deadbeef > "$RA_DIR/bad.json"
RA_GOOD=$(python3 "$SCRIPT_DIR/scripts/role-ab.py" check "$RA_DIR/good.json" 2>&1); RA_GOOD_RC=$?
RA_BAD=$(python3 "$SCRIPT_DIR/scripts/role-ab.py" check "$RA_DIR/bad.json" 2>&1); RA_BAD_RC=$?
if [ "$RA_GOOD_RC" -eq 0 ] && [ "$RA_BAD_RC" -ne 0 ] && echo "$RA_BAD" | grep -q 'is not a commit'; then
  check "role-ab check: accepts a valid spec, rejects a bad base commit" "$PASS"
else
  check "role-ab check: accepts a valid spec, rejects a bad base commit (good=$RA_GOOD_RC: $RA_GOOD; bad=$RA_BAD_RC)" "$FAIL"
fi
rm -rf "$RA_DIR"

# ---------------------------------------------------------------------------
# Check -- the commit-msg hook rejects the message that shipped with hard STE
#   findings in 05137ae and accepts the clean message of f017cc5. Without a
#   linter it warns and allows the commit. CI has no linter, so CI runs only
#   that last part.
# ---------------------------------------------------------------------------

CM_HOOK="$SCRIPT_DIR/.githooks/commit-msg"
CM_DIR=$(mktemp -d)
cat > "$CM_DIR/bad" <<'MSGEOF'
fix: clear the shellcheck findings in the role-spend and role-ab checks

CI failed on shellcheck for three findings in the new verify.sh checks:
SC2016 for a dollar sign in single quotes, SC2059 for a variable printf
format, and SC2034 for an unused variable. The checks now use a fixed-string
grep, a literal printf format in a helper, and print the role-ab output when
they fail.
MSGEOF
cat > "$CM_DIR/good" <<'MSGEOF'
feat: add role-spend and role-ab to measure model tiers

`scripts/role-spend.py` reads the local subagent transcripts. It reports the
model that each role ran on, the token use, and the estimated cost per role.
MSGEOF
STE_LINT=/nonexistent bash "$CM_HOOK" "$CM_DIR/bad" >/dev/null 2>&1; CM_NOLINT=$?
if [ "$CM_NOLINT" -eq 0 ]; then
  check "commit-msg hook: without a linter, warns and allows the commit" "$PASS"
else
  check "commit-msg hook: without a linter, warns and allows the commit (exit $CM_NOLINT)" "$FAIL"
fi
CM_LINT="${STE_LINT:-$HOME/.claude/skills/asd-ste100/scripts/ste-lint.py}"
if [ -f "$CM_LINT" ]; then
  CM_BAD_OUT=$(bash "$CM_HOOK" "$CM_DIR/bad" 2>&1); CM_BAD=$?
  bash "$CM_HOOK" "$CM_DIR/good" >/dev/null 2>&1; CM_GOOD=$?
  if [ "$CM_BAD" -ne 0 ] && [ "$CM_GOOD" -eq 0 ] && echo "$CM_BAD_OUT" | grep -q 'long-sentence'; then
    check "commit-msg hook: rejects the 05137ae message, accepts a clean one" "$PASS"
  else
    check "commit-msg hook: rejects the 05137ae message, accepts a clean one (bad=$CM_BAD good=$CM_GOOD)" "$FAIL"
  fi
else
  echo "[-] commit-msg hook: STE check skipped, no linter at $CM_LINT"
fi
rm -rf "$CM_DIR"

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------

echo ""
if [ "$ALL_PASS" -eq 1 ]; then
  echo "All checks passed."
  exit 0
else
  echo "One or more checks failed."
  exit 1
fi
