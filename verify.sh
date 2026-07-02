#!/usr/bin/env bash
# verify.sh -- Standalone verification for Agentic Workflow Framework
# Checks that the framework is correctly installed in ~/.claude/
# Prints [x] for pass, [ ] for fail. Exits 1 if any check fails.
# Can be run standalone after manual edits, or called by install.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# State A -- no .localdev/workflow dir
STATE_A=$(cd /tmp && bash -c 'if [ -d .localdev/workflow ]; then found=0; if grep -qE '"'"'^## [0-9]{4}-'"'"' .localdev/workflow/blockers.md 2>/dev/null; then echo "active blockers"; found=1; fi; for f in .localdev/workflow/handoffs/*.md; do [ -e "$f" ] && { echo "open handoff"; found=1; }; done; if [ "$found" -eq 0 ]; then echo "armed"; fi; fi' 2>/dev/null)
[ -z "$STATE_A" ]
check "SessionStart state A (no .localdev/workflow): silent" "$?"

# State B -- .localdev/workflow exists, no blockers
TMPDIR_B=$(mktemp -d)
mkdir -p "$TMPDIR_B/.localdev/workflow/handoffs"
STATE_B=$(cd "$TMPDIR_B" && bash -c 'if [ -d .localdev/workflow ]; then found=0; if grep -qE '"'"'^## [0-9]{4}-'"'"' .localdev/workflow/blockers.md 2>/dev/null; then echo "active blockers"; found=1; fi; for f in .localdev/workflow/handoffs/*.md; do [ -e "$f" ] && { echo "open handoff"; found=1; }; done; if [ "$found" -eq 0 ]; then echo "armed"; fi; fi' 2>/dev/null)
rm -rf "$TMPDIR_B"
echo "$STATE_B" | grep -q 'armed'
check "SessionStart state B (no blockers): prints 'armed'" "$?"

# State C -- blockers.md has valid entry header
TMPDIR_C=$(mktemp -d)
mkdir -p "$TMPDIR_C/.localdev/workflow/handoffs"
echo '## 2026-04-16 14:00 -- test' > "$TMPDIR_C/.localdev/workflow/blockers.md"
STATE_C=$(cd "$TMPDIR_C" && bash -c 'if [ -d .localdev/workflow ]; then found=0; if grep -qE '"'"'^## [0-9]{4}-'"'"' .localdev/workflow/blockers.md 2>/dev/null; then echo "active blockers"; found=1; fi; for f in .localdev/workflow/handoffs/*.md; do [ -e "$f" ] && { echo "open handoff"; found=1; }; done; if [ "$found" -eq 0 ]; then echo "armed"; fi; fi' 2>/dev/null)
rm -rf "$TMPDIR_C"
echo "$STATE_C" | grep -q 'active blockers'
check "SessionStart state C (active blocker): prints blocker warning" "$?"

# ---------------------------------------------------------------------------
# Check 7 -- repo structural integrity (ported from Codex validate.mjs)
# Validates the source repo at $SCRIPT_DIR, not the ~/.claude/ install.
# ---------------------------------------------------------------------------

# 7a -- .claude-plugin/plugin.json exists and is valid JSON
PLUGIN_JSON="$SCRIPT_DIR/.claude-plugin/plugin.json"
if [ -f "$PLUGIN_JSON" ]; then
  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$PLUGIN_JSON" 2>/dev/null
  check ".claude-plugin/plugin.json exists and is valid JSON" "$?"
else
  check ".claude-plugin/plugin.json exists and is valid JSON" "$FAIL"
fi

# 7b -- all 10 agent files exist
AGENTS=(planner auditor reviewer builder-smart builder-fast builder-trivial finder researcher tester watcher)
MISSING_AGENTS=0
for a in "${AGENTS[@]}"; do
  [ -f "$SCRIPT_DIR/agents/$a.md" ] || { MISSING_AGENTS=1; break; }
done
check "all 10 agent files exist in agents/" "$MISSING_AGENTS"

# 7c -- all 5 command files exist
COMMANDS=(agentic init-agentic handoff blocker known-issue)
MISSING_COMMANDS=0
for c in "${COMMANDS[@]}"; do
  [ -f "$SCRIPT_DIR/commands/$c.md" ] || { MISSING_COMMANDS=1; break; }
done
check "all 5 command files exist in commands/" "$MISSING_COMMANDS"

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
for h in orchestrator.sh inject-agentic-context.sh allow-workflow-paths.sh; do
  [ -f "$SCRIPT_DIR/hooks/$h" ] && bash -n "$SCRIPT_DIR/hooks/$h" 2>/dev/null
  check "hooks/$h exists in repo and parses" "$?"
done

# ---------------------------------------------------------------------------
# Check 8 -- every repo skill is installed in ~/.claude/skills/
#            (list derived from repo contents)
# ---------------------------------------------------------------------------

for skill_dir in "$SCRIPT_DIR/skills"/*/; do
  [ -d "$skill_dir" ] || continue
  s="$(basename "$skill_dir")"
  test -f ~/.claude/skills/"$s"/SKILL.md
  check "~/.claude/skills/$s/SKILL.md exists" "$?"
done

# ---------------------------------------------------------------------------
# Check 9 -- settings.json permissions.allow contains framework globs and
#            does NOT contain any stale .claude/mytasks glob
# ---------------------------------------------------------------------------

python3 - ~/.claude/settings.json <<'PYEOF'
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
check "settings.json permissions.allow contains the 4 .localdev/workflow globs" "$?"

python3 - ~/.claude/settings.json <<'PYEOF'
import json, sys, os
path = sys.argv[1]
if not os.path.isfile(path):
    sys.exit(0)
data = json.load(open(path))
allow = data.get("permissions", {}).get("allow", [])
stale = [g for g in allow if '.claude/mytasks' in g]
sys.exit(1 if stale else 0)
PYEOF
check "settings.json permissions.allow contains NO stale .claude/mytasks globs" "$?"

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
