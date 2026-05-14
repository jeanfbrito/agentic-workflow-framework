#!/usr/bin/env bash
# verify.sh -- Standalone verification for Agentic Workflow Framework
# Checks that the framework is correctly installed in ~/.claude/
# Prints [x] for pass, [ ] for fail. Exits 1 if any check fails.
# Can be run standalone after manual edits, or called by install.sh.

set -euo pipefail

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
# Check 1 -- 15 framework files exist
# ---------------------------------------------------------------------------

FILES=(
  ~/.claude/AGENTIC.md
  ~/.claude/agents/planner.md
  ~/.claude/agents/auditor.md
  ~/.claude/agents/finder.md
  ~/.claude/agents/researcher.md
  ~/.claude/agents/builder-fast.md
  ~/.claude/agents/builder-smart.md
  ~/.claude/agents/reviewer.md
  ~/.claude/agents/tester.md
  ~/.claude/commands/agentic.md
  ~/.claude/commands/init-agentic.md
  ~/.claude/commands/handoff.md
  ~/.claude/commands/blocker.md
  ~/.claude/commands/known-issue.md
  ~/.claude/hooks/orchestrator.sh
)
ALL_FILES=0
for f in "${FILES[@]}"; do
  [ -f "$f" ] || { ALL_FILES=1; break; }
done
check "15 framework files exist in ~/.claude/" "$ALL_FILES"

# ---------------------------------------------------------------------------
# Check 2 -- orchestrator.sh is executable
# ---------------------------------------------------------------------------

test -x ~/.claude/hooks/orchestrator.sh
check "orchestrator.sh is executable" "$?"

# ---------------------------------------------------------------------------
# Check 3 -- CLAUDE.md contains @AGENTIC.md import
# ---------------------------------------------------------------------------

grep -qF '@AGENTIC.md' ~/.claude/CLAUDE.md 2>/dev/null
check "CLAUDE.md contains @AGENTIC.md" "$?"

# ---------------------------------------------------------------------------
# Check 4 -- settings.json is valid JSON and contains both hook strings
# ---------------------------------------------------------------------------

python3 -c "import json,sys; json.load(open(sys.argv[1]))" ~/.claude/settings.json 2>/dev/null
check "settings.json is valid JSON" "$?"

grep -q 'agentic: armed' ~/.claude/settings.json 2>/dev/null
check "settings.json contains SessionStart hook ('agentic: armed')" "$?"

grep -q 'orchestrator.sh' ~/.claude/settings.json 2>/dev/null
check "settings.json contains UserPromptSubmit hook ('orchestrator.sh')" "$?"

# ---------------------------------------------------------------------------
# Check 5 -- orchestrator hook short-prompt bypass + work-verb trigger
# ---------------------------------------------------------------------------

SHORT_OUT=$(echo '{"prompt":"hi"}' | bash ~/.claude/hooks/orchestrator.sh 2>/dev/null)
[ -z "$SHORT_OUT" ]
check "orchestrator hook: short prompt produces no output" "$?"

LONG_OUT=$(echo '{"prompt":"please refactor the auth middleware and add retry logic"}' | bash ~/.claude/hooks/orchestrator.sh 2>/dev/null)
echo "$LONG_OUT" | grep -q '^orchestrator:'
check "orchestrator hook: work-verb prompt produces 'orchestrator:' output" "$?"

# ---------------------------------------------------------------------------
# Check 6 -- SessionStart three-state test
# ---------------------------------------------------------------------------

# State A -- no .claude/mytasks dir
STATE_A=$(cd /tmp && bash -c 'if [ -d .claude/mytasks ]; then found=0; if grep -qE '"'"'^## [0-9]{4}-'"'"' .claude/mytasks/blockers.md 2>/dev/null; then echo "active blockers"; found=1; fi; for f in .claude/mytasks/handoffs/*.md; do [ -e "$f" ] && { echo "open handoff"; found=1; }; done; if [ "$found" -eq 0 ]; then echo "armed"; fi; fi' 2>/dev/null)
[ -z "$STATE_A" ]
check "SessionStart state A (no .claude/mytasks): silent" "$?"

# State B -- .claude/mytasks exists, no blockers
TMPDIR_B=$(mktemp -d)
mkdir -p "$TMPDIR_B/.claude/mytasks/handoffs"
STATE_B=$(cd "$TMPDIR_B" && bash -c 'if [ -d .claude/mytasks ]; then found=0; if grep -qE '"'"'^## [0-9]{4}-'"'"' .claude/mytasks/blockers.md 2>/dev/null; then echo "active blockers"; found=1; fi; for f in .claude/mytasks/handoffs/*.md; do [ -e "$f" ] && { echo "open handoff"; found=1; }; done; if [ "$found" -eq 0 ]; then echo "armed"; fi; fi' 2>/dev/null)
rm -rf "$TMPDIR_B"
echo "$STATE_B" | grep -q 'armed'
check "SessionStart state B (no blockers): prints 'armed'" "$?"

# State C -- blockers.md has valid entry header
TMPDIR_C=$(mktemp -d)
mkdir -p "$TMPDIR_C/.claude/mytasks/handoffs"
echo '## 2026-04-16 14:00 -- test' > "$TMPDIR_C/.claude/mytasks/blockers.md"
STATE_C=$(cd "$TMPDIR_C" && bash -c 'if [ -d .claude/mytasks ]; then found=0; if grep -qE '"'"'^## [0-9]{4}-'"'"' .claude/mytasks/blockers.md 2>/dev/null; then echo "active blockers"; found=1; fi; for f in .claude/mytasks/handoffs/*.md; do [ -e "$f" ] && { echo "open handoff"; found=1; }; done; if [ "$found" -eq 0 ]; then echo "armed"; fi; fi' 2>/dev/null)
rm -rf "$TMPDIR_C"
echo "$STATE_C" | grep -q 'active blockers'
check "SessionStart state C (active blocker): prints blocker warning" "$?"

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
