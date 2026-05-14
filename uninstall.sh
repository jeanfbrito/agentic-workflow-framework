#!/usr/bin/env bash
# uninstall.sh -- Agentic Workflow Framework global uninstaller
# Removes the 15 framework files from ~/.claude/ and strips hook/import entries.
# Does NOT remove ~/.claude/agents/, ~/.claude/commands/, or ~/.claude/hooks/
# directories -- they may contain non-framework files.

set -euo pipefail

# ---------------------------------------------------------------------------
# 1. Confirmation
# ---------------------------------------------------------------------------

YES=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y) YES=1 ;;
  esac
done

if [ "$YES" -eq 0 ]; then
  printf 'Remove Agentic Workflow Framework from ~/.claude/? (y/N) '
  read -r REPLY
  case "$REPLY" in
    y|Y|yes|YES|Yes) ;;
    *) echo "Uninstall cancelled."; exit 0 ;;
  esac
fi

echo "Uninstalling Agentic Workflow Framework..."

# ---------------------------------------------------------------------------
# 2. Remove the 15 framework files
# ---------------------------------------------------------------------------

REMOVED=()
SKIPPED=()

remove_file() {
  local f="$1"
  if [ -f "$f" ]; then
    rm "$f"
    REMOVED+=("$f")
  else
    SKIPPED+=("$f")
  fi
}

remove_file ~/.claude/AGENTIC.md
remove_file ~/.claude/agents/planner.md
remove_file ~/.claude/agents/auditor.md
remove_file ~/.claude/agents/reviewer.md
remove_file ~/.claude/agents/builder-smart.md
remove_file ~/.claude/agents/builder-fast.md
remove_file ~/.claude/agents/finder.md
remove_file ~/.claude/agents/researcher.md
remove_file ~/.claude/agents/tester.md
remove_file ~/.claude/commands/agentic.md
remove_file ~/.claude/commands/init-agentic.md
remove_file ~/.claude/commands/handoff.md
remove_file ~/.claude/commands/blocker.md
remove_file ~/.claude/commands/known-issue.md
remove_file ~/.claude/hooks/orchestrator.sh

# ---------------------------------------------------------------------------
# 3. Strip @AGENTIC.md from CLAUDE.md
# ---------------------------------------------------------------------------

CLAUDE_MD=~/.claude/CLAUDE.md
CLAUDE_MD_NAMED_BACKUP="$CLAUDE_MD.bak.agentic-workflow-framework"
CLAUDE_MD_ACTION=""

if [ -f "$CLAUDE_MD" ]; then
  if [ -f "$CLAUDE_MD_NAMED_BACKUP" ]; then
    # Restore from the original pre-installation snapshot
    cp "$CLAUDE_MD_NAMED_BACKUP" "$CLAUDE_MD"
    rm "$CLAUDE_MD_NAMED_BACKUP"
    CLAUDE_MD_ACTION="restored from named backup and removed $CLAUDE_MD_NAMED_BACKUP"
  elif grep -qF '@AGENTIC.md' "$CLAUDE_MD"; then
    # No named backup -- fall back to stripping the import line
    # Use python3 for portability (BSD sed and GNU sed differ on in-place flags).
    python3 - "$CLAUDE_MD" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as fh:
    lines = fh.readlines()
filtered = [l for l in lines if l.rstrip('\n') != '@AGENTIC.md']
# Collapse consecutive blank lines that may have been left behind
out = []
prev_blank = False
for l in filtered:
    is_blank = l.strip() == ''
    if is_blank and prev_blank:
        continue
    out.append(l)
    prev_blank = is_blank
with open(path, 'w') as fh:
    fh.writelines(out)
PYEOF
    CLAUDE_MD_ACTION="stripped @AGENTIC.md line (no named backup found)"
  else
    CLAUDE_MD_ACTION="@AGENTIC.md line not found -- nothing to strip"
  fi
else
  CLAUDE_MD_ACTION="CLAUDE.md not found -- nothing to do"
fi

# ---------------------------------------------------------------------------
# 4. Strip hook entries from settings.json
# ---------------------------------------------------------------------------

SETTINGS_JSON=~/.claude/settings.json
SETTINGS_NAMED_BACKUP="$SETTINGS_JSON.bak.agentic-workflow-framework"
SETTINGS_ACTION=""

if [ -f "$SETTINGS_JSON" ] && [ -s "$SETTINGS_JSON" ]; then
  if [ -f "$SETTINGS_NAMED_BACKUP" ]; then
    # Restore from the original pre-installation snapshot
    cp "$SETTINGS_NAMED_BACKUP" "$SETTINGS_JSON"
    rm "$SETTINGS_NAMED_BACKUP"
    SETTINGS_ACTION="restored from named backup and removed $SETTINGS_NAMED_BACKUP"
  else
    # No named backup -- fall back to stripping the hook entries
    python3 - "$SETTINGS_JSON" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as fh:
    data = json.load(fh)

hooks = data.get("hooks", {})

def strip_entries(arr, marker):
    return [e for e in arr if marker not in json.dumps(e)]

changed = False
if "SessionStart" in hooks:
    before = len(hooks["SessionStart"])
    hooks["SessionStart"] = strip_entries(hooks["SessionStart"], "agentic: armed")
    if len(hooks["SessionStart"]) != before:
        changed = True
        print("REMOVED_SS")
    else:
        print("SS_NOT_FOUND")

if "UserPromptSubmit" in hooks:
    before = len(hooks["UserPromptSubmit"])
    hooks["UserPromptSubmit"] = strip_entries(hooks["UserPromptSubmit"], "orchestrator.sh")
    if len(hooks["UserPromptSubmit"]) != before:
        changed = True
        print("REMOVED_UP")
    else:
        print("UP_NOT_FOUND")

if changed:
    data["hooks"] = hooks
    with open(path, 'w') as fh:
        json.dump(data, fh, indent=2)
PYEOF
    SETTINGS_ACTION="stripped hook entries (no named backup found)"
  fi
else
  SETTINGS_ACTION="settings.json not found or empty -- nothing to do"
fi

# ---------------------------------------------------------------------------
# 5. Summary
# ---------------------------------------------------------------------------

echo ""
echo "--- Summary ---"
echo ""

echo "Files removed (${#REMOVED[@]}):"
for f in "${REMOVED[@]}"; do
  echo "  $f"
done

if [ "${#SKIPPED[@]}" -gt 0 ]; then
  echo ""
  echo "Files not found (already absent):"
  for f in "${SKIPPED[@]}"; do
    echo "  $f"
  done
fi

echo ""
echo "CLAUDE.md: $CLAUDE_MD_ACTION"
echo "settings.json: $SETTINGS_ACTION"
echo ""
echo "Uninstall complete. Directories ~/.claude/agents/, ~/.claude/commands/,"
echo "and ~/.claude/hooks/ were not removed (may contain non-framework files)."
