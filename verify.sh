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
    "Write(.localdev/workflow/**)",
    "Edit(.localdev/workflow/**)",
    "Write(.localdev/workflow/handoffs/**)",
    "Edit(.localdev/workflow/handoffs/**)",
]
missing = [g for g in REQUIRED if g not in allow]
sys.exit(1 if missing else 0)
PYEOF
then
  check "settings.json permissions.allow contains the 4 .localdev/workflow globs" "$PASS"
else
  check "settings.json permissions.allow contains the 4 .localdev/workflow globs" "$FAIL"
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
# Check 10 -- agent model bindings are consistent with AGENTIC.md's
#             Agent Roles bullets. Both sides are parsed fresh at runtime
#             (no hardcoded bindings) so this doesn't go stale as tiers
#             shift. Tolerant: only fails when AGENTIC.md's role bullet
#             names a model alias (opus/sonnet/haiku/inherit) that conflicts
#             with the agent's frontmatter `model:` value; a bullet with no
#             explicit alias (just a tier word like "reasoning"/"smart"/
#             "fast") is not compared.
# ---------------------------------------------------------------------------

for agent_src in "$SCRIPT_DIR"/agents/*.md; do
  agent_name="$(basename "$agent_src" .md)"
  fm_model="$(grep -m1 '^model:' "$agent_src" | sed 's/^model:[[:space:]]*//')"
  role_line="$(grep -E "^- \*\*${agent_name}\*\*" "$SCRIPT_DIR/AGENTIC.md" | head -n1)"
  if [ -z "$role_line" ] || [ -z "$fm_model" ]; then
    check "model binding consistent: $agent_name" "$PASS"
    continue
  fi
  bracket="$(echo "$role_line" | grep -oE '\[[^]]*\]' | head -n1)"
  conflict=0
  for alias in opus sonnet haiku inherit; do
    if echo "$bracket" | grep -qw "$alias" && [ "$alias" != "$fm_model" ]; then
      conflict=1
    fi
  done
  if [ "$conflict" -eq 0 ]; then
    check "model binding consistent: $agent_name (frontmatter=$fm_model, AGENTIC.md=$bracket)" "$PASS"
  else
    check "model binding consistent: $agent_name (frontmatter=$fm_model, AGENTIC.md=$bracket)" "$FAIL"
  fi
done

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
