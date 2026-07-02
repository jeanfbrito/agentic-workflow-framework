#!/usr/bin/env bash
# uninstall.sh -- Agentic Workflow Framework global uninstaller
# Removes the framework files + skills/ dirs from ~/.claude/ and strips
# hook/import entries and framework permission globs from settings.json.
# Does NOT remove ~/.claude/agents/, ~/.claude/commands/, ~/.claude/hooks/,
# or ~/.claude/skills/ directories -- they may contain non-framework files.
#
# Default: surgical strip of framework-added lines/entries only -- preserves
# anything you added to CLAUDE.md / settings.json after installing.
# --restore-backup: wholesale-restore CLAUDE.md and settings.json from the
#   pre-install backup snapshot (if present), discarding ALL edits made
#   since install -- framework or not. Use only for a full revert.

set -euo pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required but not found in PATH." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. Confirmation
# ---------------------------------------------------------------------------

YES=0
RESTORE_BACKUP=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y) YES=1 ;;
    --restore-backup) RESTORE_BACKUP=1 ;;
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
# 2. Remove framework files
#    Agent/command lists are derived from the repo (agents/*.md,
#    commands/*.md), mirroring install.sh's dynamic loops, so removals stay
#    in sync with the roster without a manual edit here.
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
for agent_src in "$SCRIPT_DIR"/agents/*.md; do
  remove_file ~/.claude/agents/"$(basename "$agent_src")"
done
for cmd_src in "$SCRIPT_DIR"/commands/*.md; do
  remove_file ~/.claude/commands/"$(basename "$cmd_src")"
done
remove_file ~/.claude/hooks/orchestrator.sh

# ---------------------------------------------------------------------------
# 2b. Remove framework skill dirs
#     Derive names from repo skills/*/ when available; fall back to known two.
# ---------------------------------------------------------------------------

REMOVED_SKILLS=()

if [ -d "$SCRIPT_DIR/skills" ]; then
  for skill_src in "$SCRIPT_DIR/skills"/*/; do
    [ -d "$skill_src" ] || continue
    skill_name="$(basename "$skill_src")"
    if [ -d ~/.claude/skills/"$skill_name" ]; then
      rm -rf ~/.claude/skills/"$skill_name"
      REMOVED_SKILLS+=("$skill_name")
    fi
  done
else
  # Fallback: remove the two known skill dirs
  for skill_name in agentic-workflow personal-engineering-rules; do
    if [ -d ~/.claude/skills/"$skill_name" ]; then
      rm -rf ~/.claude/skills/"$skill_name"
      REMOVED_SKILLS+=("$skill_name")
    fi
  done
fi

# ---------------------------------------------------------------------------
# 3. Strip @AGENTIC.md from CLAUDE.md
#    Default: surgical strip of the import line only -- preserves anything
#    added to CLAUDE.md after install. --restore-backup wholesale-restores
#    the pre-install snapshot instead (destroys later edits).
# ---------------------------------------------------------------------------

CLAUDE_MD=~/.claude/CLAUDE.md
CLAUDE_MD_NAMED_BACKUP="$CLAUDE_MD.bak.agentic-workflow-framework"
CLAUDE_MD_ACTION=""

if [ -f "$CLAUDE_MD" ]; then
  if [ "$RESTORE_BACKUP" -eq 1 ] && [ -f "$CLAUDE_MD_NAMED_BACKUP" ]; then
    # Restore from the original pre-installation snapshot (--restore-backup)
    cp "$CLAUDE_MD_NAMED_BACKUP" "$CLAUDE_MD"
    rm "$CLAUDE_MD_NAMED_BACKUP"
    CLAUDE_MD_ACTION="restored from named backup and removed $CLAUDE_MD_NAMED_BACKUP (--restore-backup)"
  elif grep -qF '@AGENTIC.md' "$CLAUDE_MD"; then
    # Surgical strip -- use python3 for portability (BSD sed and GNU sed differ on in-place flags).
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
    CLAUDE_MD_ACTION="stripped @AGENTIC.md line"
    if [ -f "$CLAUDE_MD_NAMED_BACKUP" ]; then
      CLAUDE_MD_ACTION="$CLAUDE_MD_ACTION (backup preserved at $CLAUDE_MD_NAMED_BACKUP -- rerun with --restore-backup to revert fully)"
    fi
  else
    CLAUDE_MD_ACTION="@AGENTIC.md line not found -- nothing to strip"
  fi
else
  CLAUDE_MD_ACTION="CLAUDE.md not found -- nothing to do"
fi

# ---------------------------------------------------------------------------
# 4. Strip hook entries from settings.json
#    Default: surgical strip of framework hook entries + permission globs
#    only -- preserves anything added to settings.json after install.
#    --restore-backup wholesale-restores the pre-install snapshot instead
#    (destroys later edits).
# ---------------------------------------------------------------------------

SETTINGS_JSON=~/.claude/settings.json
SETTINGS_NAMED_BACKUP="$SETTINGS_JSON.bak.agentic-workflow-framework"
SETTINGS_ACTION=""

if [ -f "$SETTINGS_JSON" ] && [ -s "$SETTINGS_JSON" ]; then
  if [ "$RESTORE_BACKUP" -eq 1 ] && [ -f "$SETTINGS_NAMED_BACKUP" ]; then
    # Restore from the original pre-installation snapshot (--restore-backup)
    cp "$SETTINGS_NAMED_BACKUP" "$SETTINGS_JSON"
    rm "$SETTINGS_NAMED_BACKUP"
    SETTINGS_ACTION="restored from named backup and removed $SETTINGS_NAMED_BACKUP (--restore-backup)"
  else
    # Surgical strip of the hook entries and framework perms
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

# Strip framework permission globs (both current .localdev/workflow and
# stale .claude/mytasks variants) from permissions.allow
FRAMEWORK_GLOBS = {
    "Write(.localdev/workflow/**)",
    "Edit(.localdev/workflow/**)",
    "Write(.localdev/workflow/handoffs/**)",
    "Edit(.localdev/workflow/handoffs/**)",
    "Write(docs/KNOWN_ISSUES.md)",
    "Edit(docs/KNOWN_ISSUES.md)",
}
allow = data.get("permissions", {}).get("allow", [])
before_perms = len(allow)
allow = [g for g in allow
         if g not in FRAMEWORK_GLOBS and '.claude/mytasks' not in g]
perms_removed = before_perms - len(allow)
if perms_removed > 0:
    data.setdefault("permissions", {})["allow"] = allow
    changed = True
    print(f"REMOVED_PERMS:{perms_removed}")
else:
    print("PERMS_NOT_FOUND")

if changed:
    data["hooks"] = hooks
    with open(path, 'w') as fh:
        json.dump(data, fh, indent=2)
PYEOF
    SETTINGS_ACTION="stripped hook entries and framework permission globs"
    if [ -f "$SETTINGS_NAMED_BACKUP" ]; then
      SETTINGS_ACTION="$SETTINGS_ACTION (backup preserved at $SETTINGS_NAMED_BACKUP -- rerun with --restore-backup to revert fully)"
    fi
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
if [ "${#REMOVED_SKILLS[@]}" -gt 0 ]; then
  echo "Skills removed (${#REMOVED_SKILLS[@]}):"
  for s in "${REMOVED_SKILLS[@]}"; do
    echo "  ~/.claude/skills/$s"
  done
else
  echo "Skills: none found to remove"
fi

echo ""
echo "CLAUDE.md: $CLAUDE_MD_ACTION"
echo "settings.json: $SETTINGS_ACTION"
echo ""
echo "Uninstall complete. Directories ~/.claude/agents/, ~/.claude/commands/,"
echo "~/.claude/hooks/, and ~/.claude/skills/ were not removed (may contain"
echo "non-framework files)."
