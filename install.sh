#!/usr/bin/env bash
# install.sh -- Agentic Workflow Framework global installer
# Idempotent: safe to re-run; overwrites framework files, preserves existing
# CLAUDE.md content and settings.json entries (appends only).

set -euo pipefail

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

# ---------------------------------------------------------------------------
# 2. Directories
# ---------------------------------------------------------------------------

mkdir -p ~/.claude/agents
mkdir -p ~/.claude/commands
mkdir -p ~/.claude/hooks

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

install_file "$SCRIPT_DIR/agents/planner.md"             ~/.claude/agents/planner.md
install_file "$SCRIPT_DIR/agents/auditor.md"             ~/.claude/agents/auditor.md
install_file "$SCRIPT_DIR/agents/reviewer.md"            ~/.claude/agents/reviewer.md
install_file "$SCRIPT_DIR/agents/builder-smart.md"       ~/.claude/agents/builder-smart.md
install_file "$SCRIPT_DIR/agents/builder-fast.md"        ~/.claude/agents/builder-fast.md
install_file "$SCRIPT_DIR/agents/finder.md"              ~/.claude/agents/finder.md
install_file "$SCRIPT_DIR/agents/researcher.md"          ~/.claude/agents/researcher.md
install_file "$SCRIPT_DIR/agents/tester.md"              ~/.claude/agents/tester.md

install_file "$SCRIPT_DIR/commands/agentic.md"           ~/.claude/commands/agentic.md
install_file "$SCRIPT_DIR/commands/init-agentic.md"      ~/.claude/commands/init-agentic.md
install_file "$SCRIPT_DIR/commands/handoff.md"           ~/.claude/commands/handoff.md
install_file "$SCRIPT_DIR/commands/blocker.md"           ~/.claude/commands/blocker.md
install_file "$SCRIPT_DIR/commands/known-issue.md"       ~/.claude/commands/known-issue.md

install_file "$SCRIPT_DIR/hooks/orchestrator.sh"         ~/.claude/hooks/orchestrator.sh

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

# --- SessionStart ---
session_start = hooks.setdefault("SessionStart", [])
ss_command = (
    'if [ -d .claude/mytasks ]; then found=0; '
    'if grep -qE \'^## [0-9]{4}-\' .claude/mytasks/blockers.md 2>/dev/null; '
    'then echo \'⚠️  Active blockers: .claude/mytasks/blockers.md\'; found=1; fi; '
    'for f in .claude/mytasks/handoffs/*.md; do '
    '[ -e "$f" ] && { echo "📋 Open handoff: $f"; found=1; }; done; '
    'if [ "$found" -eq 0 ]; then echo \'✓ agentic: armed\'; fi; fi'
)
already_ss = any(
    'agentic: armed' in json.dumps(entry)
    for entry in session_start
)
if not already_ss:
    session_start.append({
        "matcher": "",
        "hooks": [{"type": "command", "command": ss_command}]
    })
    print("SS_ADDED")
else:
    print("SS_SKIPPED")

# --- UserPromptSubmit ---
user_prompt = hooks.setdefault("UserPromptSubmit", [])
already_up = any(
    'orchestrator.sh' in json.dumps(entry)
    for entry in user_prompt
)
if not already_up:
    user_prompt.append({
        "matcher": "",
        "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/orchestrator.sh"}]
    })
    print("UP_ADDED")
else:
    print("UP_SKIPPED")

with open(path, 'w') as fh:
    json.dump(data, fh, indent=2)
PYEOF

# ---------------------------------------------------------------------------
# 7. Verification
# ---------------------------------------------------------------------------

echo ""
echo "--- Verification ---"
bash "$SCRIPT_DIR/verify.sh"
ALL_PASS=$?

# ---------------------------------------------------------------------------
# 8. Summary
# ---------------------------------------------------------------------------

echo ""
echo "--- Summary ---"
echo ""

if [ "$LINK" -eq 1 ]; then
  echo "Framework files: linked (dev mode) -- 15 symlinks to $SCRIPT_DIR"
else
  echo "Framework files: copied (15 files to ~/.claude/)"
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
if [ -f "$SETTINGS_BACKUP" ]; then
  echo "  Backup: $SETTINGS_BACKUP (one-shot, preserved across reinstalls)"
fi

echo ""
echo "How to use:"
echo "  /agentic <task>         Front door for any non-trivial task. Tier is inferred;"
echo "                          use --tier=trivial|medium|full to override."
echo "  /init-agentic           Scaffold .claude/mytasks/ in the current project."
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
