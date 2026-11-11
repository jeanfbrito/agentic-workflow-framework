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
LINK=1   # Default: symlink into this clone, so a git pull updates the install.
WIKI_DIR=""
for arg in "$@"; do
  case "$arg" in
    --yes|-y) YES=1 ;;
    --link)   LINK=1 ;;
    --copy)   LINK=0 ;;
    --wiki-dir=*) WIKI_DIR="${arg#--wiki-dir=}" ;;
    --help|-h)
      echo "Usage: ./install.sh [--yes|-y] [--copy] [--wiki-dir=PATH]"
      echo ""
      echo "  --yes, -y         Skip the confirmation prompt."
      echo "  (default)         Symlink framework files into this clone. A git pull or"
      echo "                    a branch switch in the clone changes the install."
      echo "                    Windows: needs Developer Mode (Settings > System >"
      echo "                    For developers)."
      echo "  --copy            Copy the files. The install does not follow the clone,"
      echo "                    and Windows does not need Developer Mode."
      echo "  --link            Accepted for older scripts. Same as the default."
      echo "  --wiki-dir=PATH   Folder for wiki pages (an Obsidian vault or any folder"
      echo "                    of Markdown notes). Saved in ~/.claude/agentic-config.json."
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

# Windows: defines `python3` when only `python` or `py` is a real Python 3.
# macOS and Linux: no change.
# shellcheck source=hooks/agentic-python.sh
. "$SCRIPT_DIR/hooks/agentic-python.sh"

if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 8))' >/dev/null 2>&1; then
  echo "ERROR: Python 3.8 or later is required, and none was found." >&2
  if agentic_is_windows; then
    echo "  Install it with: winget install Python.Python.3.12" >&2
    echo "  The Microsoft Store 'python3' alias is not a real Python. Turn it off in" >&2
    echo "  Settings > Apps > Advanced app settings > App execution aliases." >&2
  else
    echo "  Install python3 and run this script again." >&2
  fi
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  JQ_MISSING=1
else
  JQ_MISSING=0
fi

# Windows: Git Bash `ln -s` makes a COPY with no warning unless it is told to
# make a real symlink (winsymlinks:nativestrict). A real symlink needs
# Developer Mode, so the default link install on Windows requires it. This
# check runs before the installer changes anything, and it stops with the steps
# to turn it on. --copy makes no symlinks and does not need Developer Mode.
# macOS and Linux use plain `ln -sfn`.
if agentic_is_windows; then
  export MSYS="${MSYS:+$MSYS }winsymlinks:nativestrict"
  export CYGWIN="${CYGWIN:+$CYGWIN }winsymlinks:nativestrict"
fi

require_windows_symlinks() {
  local probe
  probe=$(mktemp -d)
  if ! ln -s "$probe" "$probe/link" 2>/dev/null; then
    rm -rf "$probe"
    echo "ERROR: the link install on Windows needs Developer Mode, which lets you make symlinks." >&2
    echo "  1. Open Settings > System > For developers and turn on Developer Mode." >&2
    echo "  2. Open a new Git Bash and run ./install.sh again." >&2
    echo "  Or run ./install.sh --copy: files are copied, and Developer Mode is not needed." >&2
    exit 1
  fi
  rm -f "$probe/link"
  rm -rf "$probe"
}

if [ "$LINK" -eq 1 ] && agentic_is_windows; then
  require_windows_symlinks
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

link_path() {
  ln -sfn "$1" "$2"
}

install_file() {
  local src="$1"
  local dst="$2"
  if [ "$LINK" -eq 1 ]; then
    link_path "$src" "$dst"
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
install_file "$SCRIPT_DIR/hooks/session-scan.sh"         ~/.claude/hooks/session-scan.sh
install_file "$SCRIPT_DIR/hooks/pre-compact.sh"          ~/.claude/hooks/pre-compact.sh
install_file "$SCRIPT_DIR/hooks/stop-ledger-audit.sh"    ~/.claude/hooks/stop-ledger-audit.sh
install_file "$SCRIPT_DIR/scripts/ledger-append.sh"      ~/.claude/hooks/ledger-append.sh
install_file "$SCRIPT_DIR/hooks/skill-review-nudge.sh"   ~/.claude/hooks/skill-review-nudge.sh
install_file "$SCRIPT_DIR/hooks/test-run-advisor.sh"     ~/.claude/hooks/test-run-advisor.sh
install_file "$SCRIPT_DIR/hooks/agentic-python.sh"       ~/.claude/hooks/agentic-python.sh

# ---------------------------------------------------------------------------
# 3b. Skills -- dynamic install (loop over skills/*/)
#     Adding a new skills/<name>/ to the repo automatically installs it here.
# ---------------------------------------------------------------------------

INSTALLED_SKILLS=()

for skill_src in "$SCRIPT_DIR/skills"/*/; do
  [ -d "$skill_src" ] || continue
  skill_src="${skill_src%/}"
  skill_name="$(basename "$skill_src")"
  if [ "$LINK" -eq 1 ]; then
    rm -rf ~/.claude/skills/"$skill_name"
    link_path "$skill_src" ~/.claude/skills/"$skill_name"
  else
    rm -rf ~/.claude/skills/"$skill_name"
    cp -R "$skill_src" ~/.claude/skills/"$skill_name"
  fi
  INSTALLED_SKILLS+=("$skill_name")
done

# The weekly skill review reads this manifest to tell framework skills and
# commands from the user's own.
{
  for s in "${INSTALLED_SKILLS[@]}"; do echo "$s"; done
  for cmd_src in "$SCRIPT_DIR/commands"/*.md; do basename "$cmd_src" .md; done
} > ~/.claude/skills/.agentic-framework-skills

# ---------------------------------------------------------------------------
# 4. Executable bit
# ---------------------------------------------------------------------------

chmod +x ~/.claude/hooks/orchestrator.sh
chmod +x ~/.claude/hooks/session-scan.sh
chmod +x ~/.claude/hooks/pre-compact.sh
chmod +x ~/.claude/hooks/stop-ledger-audit.sh
chmod +x ~/.claude/hooks/ledger-append.sh
chmod +x ~/.claude/hooks/skill-review-nudge.sh
chmod +x ~/.claude/hooks/test-run-advisor.sh

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
ss_command = "bash ~/.claude/hooks/session-scan.sh"
# Two markers: 'agentic: armed' catches the OLD pre-script inline blob (the
# digest text used to be embedded directly in this command string) so an
# upgrade replaces it instead of leaving a stale duplicate; 'session-scan.sh'
# catches this entry itself so repeat installs stay idempotent.
before_ss = len(session_start)
session_start = strip_framework(session_start, 'agentic: armed')
session_start = strip_framework(session_start, 'session-scan.sh')
session_start.append({
    "matcher": "",
    "hooks": [{"type": "command", "command": ss_command}]
})
hooks["SessionStart"] = session_start
print("SS_REPLACED" if before_ss > len(session_start) - 1 else "SS_ADDED")

# --- SessionStart: weekly skill review ---
# Marker 'skill-review-nudge.sh' identifies this entry.
session_start = strip_framework(hooks["SessionStart"], 'skill-review-nudge.sh')
session_start.append({
    "matcher": "startup|resume",
    "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/skill-review-nudge.sh", "timeout": 10}]
})
hooks["SessionStart"] = session_start

# --- PreCompact ---
pre_compact = hooks.setdefault("PreCompact", [])
pc_command = "bash ~/.claude/hooks/pre-compact.sh"
# Marker 'pre-compact.sh' identifies this framework's entry -- filter then
# append keeps repeat installs idempotent.
before_pc = len(pre_compact)
pre_compact = strip_framework(pre_compact, 'pre-compact.sh')
pre_compact.append({
    "matcher": "",
    "hooks": [{"type": "command", "command": pc_command}]
})
hooks["PreCompact"] = pre_compact
print("PC_REPLACED" if before_pc > len(pre_compact) - 1 else "PC_ADDED")

# --- Stop ---
stop_hooks = hooks.setdefault("Stop", [])
stop_command = "bash ~/.claude/hooks/stop-ledger-audit.sh"
# Marker 'stop-ledger-audit.sh' identifies this framework's entry.
before_stop = len(stop_hooks)
stop_hooks = strip_framework(stop_hooks, 'stop-ledger-audit.sh')
stop_hooks.append({
    "matcher": "",
    "hooks": [{"type": "command", "command": stop_command}]
})
hooks["Stop"] = stop_hooks
print("STOP_REPLACED" if before_stop > len(stop_hooks) - 1 else "STOP_ADDED")

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

# --- PreToolUse: test-run advisor ---
# Marker 'test-run-advisor.sh' identifies this entry.
pre_tool = strip_framework(hooks.setdefault("PreToolUse", []), 'test-run-advisor.sh')
pre_tool.append({
    "matcher": "Bash",
    "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/test-run-advisor.sh", "timeout": 5}]
})
hooks["PreToolUse"] = pre_tool

# --- permissions.allow ---
# Ensure permissions and allow list exist, preserving all existing entries + order.
perms = data.setdefault("permissions", {})
allow = perms.setdefault("allow", [])

# MIGRATE: drop stale .claude/mytasks globs (old path, replaced by .localdev/workflow)
before_migrate = len(allow)
allow = [g for g in allow if '.claude/mytasks' not in g]
# MIGRATE: drop the Write(path) globs older installs granted. Claude Code
# matches file permissions only against Edit(path) rules, which cover every
# file-editing tool, and warns at startup about each Write(path) rule.
LEGACY_WRITE_GLOBS = {
    "Write(.localdev/workflow/**)",
    "Write(.localdev/workflow/handoffs/**)",
    "Write(docs/KNOWN_ISSUES.md)",
}
allow = [g for g in allow if g not in LEGACY_WRITE_GLOBS]
migrated = before_migrate - len(allow)

# GRANT: the 3 framework permission globs (add if missing, no duplicates)
FRAMEWORK_GLOBS = [
    "Edit(.localdev/workflow/**)",
    "Edit(.localdev/workflow/handoffs/**)",
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
# 6b. Wiki folder -- personal config for the weekly skill review.
#     Asked once. A reinstall keeps the saved value.
# ---------------------------------------------------------------------------

SKILL_REVIEW=~/.claude/skills/skill-review/scripts/skill_review.py
WIKI_ACTION="kept"
if [ -z "$WIKI_DIR" ] && [ "$YES" -eq 0 ] \
   && python3 "$SKILL_REVIEW" config | grep -q '"wiki_dir": null'; then
  printf 'Wiki folder for the notes Claude writes to teach you (blank to skip): '
  read -r WIKI_DIR
fi
if [ -n "$WIKI_DIR" ]; then
  if python3 "$SKILL_REVIEW" config --wiki-dir "$WIKI_DIR" >/dev/null; then
    WIKI_ACTION="set to $WIKI_DIR"
  else
    WIKI_ACTION="NOT set: $WIKI_DIR is not a directory"
  fi
fi

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
CORE_COUNT=$((9 + AGENT_COUNT + COMMAND_COUNT))  # AGENTIC.md + 7 hook files + ledger-append.sh + agents + commands
if [ "$LINK" -eq 1 ]; then
  echo "Framework files: linked -- $CORE_COUNT core symlinks + $SKILL_COUNT skill(s) to $SCRIPT_DIR"
  echo "  A git pull or a branch switch in that clone changes the install. Keep the clone in place."
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
if grep -q 'session-scan.sh' "$SETTINGS_JSON" 2>/dev/null; then
  echo "  hooks.SessionStart        -- budgeted ledger digest (present)"
fi
if grep -q 'skill-review-nudge.sh' "$SETTINGS_JSON" 2>/dev/null; then
  echo "  hooks.SessionStart        -- weekly skill review nudge (present)"
fi
if grep -q 'pre-compact.sh' "$SETTINGS_JSON" 2>/dev/null; then
  echo "  hooks.PreCompact          -- in-flight card snapshot (present)"
fi
if grep -q 'stop-ledger-audit.sh' "$SETTINGS_JSON" 2>/dev/null; then
  echo "  hooks.Stop                -- ledger hygiene audit (present)"
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
echo "Wiki folder: $WIKI_ACTION"
python3 "$SKILL_REVIEW" config | grep '"wiki_dir"' | sed 's/^/ /'
echo "  Change it with: python3 $SKILL_REVIEW config --wiki-dir <path>"

if [ "$JQ_MISSING" -eq 1 ]; then
  echo ""
  echo "Optional: jq is not installed. The test-run advisor hook stays silent without it."
  if agentic_is_windows; then
    echo "  Install it with: winget install jqlang.jq (then open a new terminal)"
  else
    echo "  Install it with your package manager (brew install jq, apt install jq)."
  fi
fi

if agentic_is_windows && ! command python3 -c '' >/dev/null 2>&1; then
  echo ""
  echo "Windows note: the hooks find Python by themselves ($AGENTIC_PYTHON)."
  echo "  Skill steps tell Claude to run 'python3', which is not a real command here."
  echo "  To make it one in Git Bash, run:"
  echo "    mkdir -p ~/bin"
  # The backslashes are literal text for the user to copy, not escapes.
  # shellcheck disable=SC2028
  echo "    printf '#!/bin/sh\\nexec \"$AGENTIC_PYTHON\" \"\$@\"\\n' > ~/bin/python3"
fi

echo ""
echo "How to use:"
echo "  /agentic <task>         Front door for any non-trivial task. Tier is inferred;"
echo "                          use --tier=trivial|medium|full to override."
echo "  /init-agentic           Scaffold .localdev/workflow/ in the current project."
echo "  /handoff <name>         Write a cross-session handoff from current context."
echo "  /blocker <summary>      Log an unresolved blocker and halt."
echo "  /known-issue <summary>  Append a platform constraint to docs/KNOWN_ISSUES.md."
echo "  /skill-review           Weekly review: which skills to keep, merge, promote or retire."
echo ""
echo "  Handle scoped work directly; use planning and authorized delegation when useful."
echo "  Continue through the requested outcome and focused verification."
echo "  'do it yourself' and 'off orchestrator' disable delegation."
echo ""

if [ "$ALL_PASS" -eq 0 ]; then
  echo "All checks passed. Installation complete."
else
  echo "One or more checks FAILED. Review output above."
  exit 1
fi
