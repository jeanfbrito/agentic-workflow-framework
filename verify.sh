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

if grep -q 'agentic: armed' ~/.claude/settings.json 2>/dev/null; then
  check "settings.json contains SessionStart hook ('agentic: armed')" "$PASS"
else
  check "settings.json contains SessionStart hook ('agentic: armed')" "$FAIL"
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
# Check 6 -- SessionStart three-state test
# ---------------------------------------------------------------------------

# State A -- no .localdev/workflow dir
STATE_A=$(cd /tmp && bash -c 'if [ -d .localdev/workflow ]; then found=0; if grep -qE '"'"'^## [0-9]{4}-'"'"' .localdev/workflow/blockers.md 2>/dev/null; then echo "active blockers"; found=1; fi; for f in .localdev/workflow/handoffs/*.md; do [ -e "$f" ] && { echo "open handoff"; found=1; }; done; if [ "$found" -eq 0 ]; then echo "armed"; fi; fi' 2>/dev/null)
if [ -z "$STATE_A" ]; then
  check "SessionStart state A (no .localdev/workflow): silent" "$PASS"
else
  check "SessionStart state A (no .localdev/workflow): silent" "$FAIL"
fi

# State B -- .localdev/workflow exists, no blockers
TMPDIR_B=$(mktemp -d)
mkdir -p "$TMPDIR_B/.localdev/workflow/handoffs"
STATE_B=$(cd "$TMPDIR_B" && bash -c 'if [ -d .localdev/workflow ]; then found=0; if grep -qE '"'"'^## [0-9]{4}-'"'"' .localdev/workflow/blockers.md 2>/dev/null; then echo "active blockers"; found=1; fi; for f in .localdev/workflow/handoffs/*.md; do [ -e "$f" ] && { echo "open handoff"; found=1; }; done; if [ "$found" -eq 0 ]; then echo "armed"; fi; fi' 2>/dev/null)
rm -rf "$TMPDIR_B"
if echo "$STATE_B" | grep -q 'armed'; then
  check "SessionStart state B (no blockers): prints 'armed'" "$PASS"
else
  check "SessionStart state B (no blockers): prints 'armed'" "$FAIL"
fi

# State C -- blockers.md has valid entry header
TMPDIR_C=$(mktemp -d)
mkdir -p "$TMPDIR_C/.localdev/workflow/handoffs"
echo '## 2026-04-16 14:00 -- test' > "$TMPDIR_C/.localdev/workflow/blockers.md"
STATE_C=$(cd "$TMPDIR_C" && bash -c 'if [ -d .localdev/workflow ]; then found=0; if grep -qE '"'"'^## [0-9]{4}-'"'"' .localdev/workflow/blockers.md 2>/dev/null; then echo "active blockers"; found=1; fi; for f in .localdev/workflow/handoffs/*.md; do [ -e "$f" ] && { echo "open handoff"; found=1; }; done; if [ "$found" -eq 0 ]; then echo "armed"; fi; fi' 2>/dev/null)
rm -rf "$TMPDIR_C"
if echo "$STATE_C" | grep -q 'active blockers'; then
  check "SessionStart state C (active blocker): prints blocker warning" "$PASS"
else
  check "SessionStart state C (active blocker): prints blocker warning" "$FAIL"
fi

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
for h in orchestrator.sh inject-agentic-context.sh allow-workflow-paths.sh; do
  if [ -f "$SCRIPT_DIR/hooks/$h" ] && bash -n "$SCRIPT_DIR/hooks/$h" 2>/dev/null; then
    check "hooks/$h exists in repo and parses" "$PASS"
  else
    check "hooks/$h exists in repo and parses" "$FAIL"
  fi
done

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
