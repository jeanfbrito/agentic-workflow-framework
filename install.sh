#!/usr/bin/env bash
# install.sh -- Agentic Workflow Framework global installer
# Idempotent: safe to re-run; overwrites framework files, preserves existing
# CLAUDE.md content. settings.json hook entries are deduped by stable marker
# (filter-then-append) so re-running never duplicates and self-heals stale entries.
# Skills under skills/ are installed dynamically -- new skills need no installer edit.
# permissions.allow is patched: stale .claude/mytasks globs are removed, framework
# .localdev/workflow and docs/KNOWN_ISSUES.md globs are added (no duplicates).

set -euo pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# 1. Confirmation
# ---------------------------------------------------------------------------

YES=0
LINK=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y) YES=1 ;;
    --link)   LINK=1 ;;
    --help|-h)
      echo "Usage: ./install.sh [--yes|-y] [--link]"
      echo ""
      echo "  --yes, -y   Skip the confirmation prompt."
      echo "  --link      Symlink framework files instead of copying (dev mode)."
      echo "              Use when iterating on the repo without reinstalling."
      exit 0
      ;;
  esac
done

if [ "$YES" -eq 0 ]; then
  printf 'Install Agentic Workflow Framework globally to ~/.claude/? (y/N) '
  read -r REPLY
  case "$REPLY" in
    y|Y|yes|YES|Yes) ;;
    *) echo "Installation cancelled."; exit 0 ;;
  esac
fi

echo "Installing Agentic Workflow Framework..."

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required but not found in PATH. Install python3 and re-run." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Directories
# ---------------------------------------------------------------------------

mkdir -p ~/.claude/agents
mkdir -p ~/.claude/commands
mkdir -p ~/.claude/hooks
mkdir -p ~/.claude/skills

# ---------------------------------------------------------------------------
# 3. Copy (or link) framework files
# ---------------------------------------------------------------------------

install_file() {
  local src="$1"
  local dst="$2"
  if [ "$LINK" -eq 1 ]; then
    ln -sfn "$src" "$dst"
  else
    cp "$src" "$dst"
  fi
}

install_file "$SCRIPT_DIR/AGENTIC.md"                    ~/.claude/AGENTIC.md

# Agents and commands install dynamically -- adding a new agents/<name>.md or
# commands/<name>.md to the repo needs no installer edit, just a re-run.
AGENT_COUNT=0
for agent_src in "$SCRIPT_DIR/agents"/*.md; do
  install_file "$agent_src" ~/.claude/agents/"$(basename "$agent_src")"
  AGENT_COUNT=$((AGENT_COUNT + 1))
done

COMMAND_COUNT=0
for cmd_src in "$SCRIPT_DIR/commands"/*.md; do
  install_file "$cmd_src" ~/.claude/commands/"$(basename "$cmd_src")"
  COMMAND_COUNT=$((COMMAND_COUNT + 1))
done

install_file "$SCRIPT_DIR/hooks/orchestrator.sh"         ~/.claude/hooks/orchestrator.sh

# ---------------------------------------------------------------------------
# 3b. Skills -- dynamic install (loop over skills/*/)
#     Adding a new skills/<name>/ to the repo automatically installs it here.
# ---------------------------------------------------------------------------

INSTALLED_SKILLS=()

for skill_src in "$SCRIPT_DIR/skills"/*/; do
  [ -d "$skill_src" ] || continue
  skill_name="$(basename "$skill_src")"
  if [ "$LINK" -eq 1 ]; then
    rm -rf ~/.claude/skills/"$skill_name"
    ln -sfn "$skill_src" ~/.claude/skills/"$skill_name"
  else
    rm -rf ~/.claude/skills/"$skill_name"
    cp -R "$skill_src" ~/.claude/skills/"$skill_name"
  fi
  INSTALLED_SKILLS+=("$skill_name")
done

# ---------------------------------------------------------------------------
# 4. Executable bit
# ---------------------------------------------------------------------------

chmod +x ~/.claude/hooks/orchestrator.sh

# ---------------------------------------------------------------------------
# 5. CLAUDE.md -- backup + ensure @AGENTIC.md import line
# ---------------------------------------------------------------------------

CLAUDE_MD=~/.claude/CLAUDE.md
CLAUDE_MD_BACKUP="$CLAUDE_MD.bak.agentic-workflow-framework"

if [ -f "$CLAUDE_MD" ] && [ ! -f "$CLAUDE_MD_BACKUP" ]; then
  cp "$CLAUDE_MD" "$CLAUDE_MD_BACKUP"
fi

if [ -f "$CLAUDE_MD" ]; then
  if ! grep -qF '@AGENTIC.md' "$CLAUDE_MD"; then
    printf '\n@AGENTIC.md\n' >> "$CLAUDE_MD"
    CLAUDE_MD_ACTION="appended @AGENTIC.md line"
  else
    CLAUDE_MD_ACTION="skipped -- @AGENTIC.md already present"
  fi
else
  printf '@AGENTIC.md\n' > "$CLAUDE_MD"
  CLAUDE_MD_ACTION="created with @AGENTIC.md line"
fi

# ---------------------------------------------------------------------------
# 6. settings.json -- backup + patch via python3
# ---------------------------------------------------------------------------

SETTINGS_JSON=~/.claude/settings.json
SETTINGS_BACKUP="$SETTINGS_JSON.bak.agentic-workflow-framework"

if [ -f "$SETTINGS_JSON" ] && [ ! -f "$SETTINGS_BACKUP" ]; then
  cp "$SETTINGS_JSON" "$SETTINGS_BACKUP"
fi

python3 - "$SETTINGS_JSON" <<'PYEOF'
import json, sys, os

path = sys.argv[1]

# Read existing or start fresh
if os.path.isfile(path) and os.path.getsize(path) > 0:
    with open(path) as fh:
        data = json.load(fh)
else:
    data = {}

hooks = data.setdefault("hooks", {})


def strip_framework(arr, marker):
    """Filter-then-append idempotency: drop any pre-existing framework
    entry (matched by a stable marker) so re-running never duplicates and
    a changed command string self-heals instead of going stale."""
    return [e for e in arr if marker not in json.dumps(e)]


# --- SessionStart ---
session_start = hooks.setdefault("SessionStart", [])
ss_command = (
    'if [ -d .localdev/workflow ]; then found=0; '
    'if grep -qE \'^## [0-9]{4}-\' .localdev/workflow/blockers.md 2>/dev/null; '
    'then echo \'⚠️  Active blockers: .localdev/workflow/blockers.md\'; found=1; fi; '
    'for f in .localdev/workflow/handoffs/*.md; do '
    '[ -e "$f" ] && { echo "📋 Open handoff: $f"; found=1; }; done; '
    'if [ "$found" -eq 0 ]; then echo \'✓ agentic: armed\'; fi; fi'
)
# Marker 'agentic: armed' is unique to this framework's SessionStart command.
before_ss = len(session_start)
session_start = strip_framework(session_start, 'agentic: armed')
session_start.append({
    "matcher": "",
    "hooks": [{"type": "command", "command": ss_command}]
})
hooks["SessionStart"] = session_start
print("SS_REPLACED" if before_ss > len(session_start) - 1 else "SS_ADDED")

# --- UserPromptSubmit ---
user_prompt = hooks.setdefault("UserPromptSubmit", [])
# Marker 'orchestrator.sh' is the stable path identifying this framework's entry.
before_up = len(user_prompt)
user_prompt = strip_framework(user_prompt, 'orchestrator.sh')
user_prompt.append({
    "matcher": "",
    "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/orchestrator.sh"}]
})
hooks["UserPromptSubmit"] = user_prompt
print("UP_REPLACED" if before_up > len(user_prompt) - 1 else "UP_ADDED")

# --- permissions.allow ---
# Ensure permissions and allow list exist, preserving all existing entries + order.
perms = data.setdefault("permissions", {})
allow = perms.setdefault("allow", [])

# MIGRATE: drop stale .claude/mytasks globs (old path, replaced by .localdev/workflow)
before_migrate = len(allow)
allow = [g for g in allow if '.claude/mytasks' not in g]
migrated = before_migrate - len(allow)

# GRANT: the 6 framework permission globs (add if missing, no duplicates)
FRAMEWORK_GLOBS = [
    "Write(.localdev/workflow/**)",
    "Edit(.localdev/workflow/**)",
    "Write(.localdev/workflow/handoffs/**)",
    "Edit(.localdev/workflow/handoffs/**)",
    "Write(docs/KNOWN_ISSUES.md)",
    "Edit(docs/KNOWN_ISSUES.md)",
]
added = 0
for glob in FRAMEWORK_GLOBS:
    if glob not in allow:
        allow.append(glob)
        added += 1

perms["allow"] = allow
data["permissions"] = perms

if migrated > 0:
    print("PERMS_MIGRATED")
if added > 0:
    print(f"PERMS_ADDED:{added}")
if migrated == 0 and added == 0:
    print("PERMS_OK")

with open(path, 'w') as fh:
    json.dump(data, fh, indent=2)
PYEOF

# ---------------------------------------------------------------------------
# 7. Verification
# ---------------------------------------------------------------------------

echo ""
echo "--- Verification ---"
if bash "$SCRIPT_DIR/verify.sh"; then
  ALL_PASS=0
else
  ALL_PASS=1
fi

# ---------------------------------------------------------------------------
# 8. Summary
# ---------------------------------------------------------------------------

echo ""
echo "--- Summary ---"
echo ""

SKILL_COUNT="${#INSTALLED_SKILLS[@]}"
CORE_COUNT=$((2 + AGENT_COUNT + COMMAND_COUNT))  # AGENTIC.md + hook + agents + commands
if [ "$LINK" -eq 1 ]; then
  echo "Framework files: linked (dev mode) -- $CORE_COUNT core symlinks + $SKILL_COUNT skill(s) to $SCRIPT_DIR"
else
  echo "Framework files: copied ($CORE_COUNT core files + $SKILL_COUNT skill(s) to ~/.claude/)"
fi

if [ "$SKILL_COUNT" -gt 0 ]; then
  echo ""
  echo "Skills installed (${SKILL_COUNT}):"
  for s in "${INSTALLED_SKILLS[@]}"; do
    echo "  ~/.claude/skills/$s"
  done
fi

echo ""
echo "CLAUDE.md: $CLAUDE_MD_ACTION"
if [ -f "$CLAUDE_MD_BACKUP" ]; then
  echo "  Backup: $CLAUDE_MD_BACKUP (one-shot, preserved across reinstalls)"
fi

echo ""
echo "settings.json hook entries:"
if grep -q 'agentic: armed' "$SETTINGS_JSON" 2>/dev/null; then
  echo "  hooks.SessionStart        -- blocker/handoff scanner (present)"
fi
if grep -q 'orchestrator.sh' "$SETTINGS_JSON" 2>/dev/null; then
  echo "  hooks.UserPromptSubmit    -- orchestrator reinforcement (present)"
fi
echo ""
echo "settings.json permissions.allow:"
python3 - "$SETTINGS_JSON" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
globs = data.get("permissions", {}).get("allow", [])
fw = [g for g in globs if '.localdev/workflow' in g or 'KNOWN_ISSUES' in g]
stale = [g for g in globs if '.claude/mytasks' in g]
for g in fw:
    print(f"  {g}")
if stale:
    print(f"  WARNING: {len(stale)} stale .claude/mytasks glob(s) still present")
if not fw:
    print("  (no framework globs found -- check install output above)")
PYEOF
if [ -f "$SETTINGS_BACKUP" ]; then
  echo "  Backup: $SETTINGS_BACKUP (one-shot, preserved across reinstalls)"
fi

echo ""
echo "How to use:"
echo "  /agentic <task>         Front door for any non-trivial task. Tier is inferred;"
echo "                          use --tier=trivial|medium|full to override."
echo "  /init-agentic           Scaffold .localdev/workflow/ in the current project."
echo "  /handoff <name>         Write a cross-session handoff from current context."
echo "  /blocker <summary>      Log an unresolved blocker and halt."
echo "  /known-issue <summary>  Append a platform constraint to docs/KNOWN_ISSUES.md."
echo ""
echo "  Orchestrator mode is active by default. Claude delegates implementation"
echo "  to subagents (builder-fast, builder-smart, finder, researcher, tester)."
echo "  'do it yourself' overrides for one turn. 'off orchestrator' disables for the session."
echo ""

if [ "$ALL_PASS" -eq 0 ]; then
  echo "All checks passed. Installation complete."
else
  echo "One or more checks FAILED. Review output above."
  exit 1
fi
