#!/usr/bin/env bash
# Windows: make `python3` start a real Python 3 (see agentic-python.sh).
case "${BASH_SOURCE[0]}" in */* | *\\*) _agentic_lib="${BASH_SOURCE[0]%[/\\]*}/agentic-python.sh" ;; *) _agentic_lib=./agentic-python.sh ;; esac
# shellcheck source=hooks/agentic-python.sh
[ -f "$_agentic_lib" ] && . "$_agentic_lib"

# allow-workflow-paths.sh -- PreToolUse hook (plugin install path).
# Marketplace installs cannot pre-grant permission globs in ~/.claude/settings.json,
# so this hook auto-allows Write/Edit on the framework's working paths instead,
# mirroring exactly what install.sh grants:
#   .localdev/workflow/**  and  docs/KNOWN_ISSUES.md
# Any other path produces no output, leaving the normal permission flow intact.

set -euo pipefail

python3 -c '
import json, os, sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

path = (data.get("tool_input") or {}).get("file_path") or ""
if not path:
    sys.exit(0)

# Normalize so ".localdev/workflow/../../secrets" cannot ride the allow rule.
norm = os.path.normpath(path)
# Windows: normpath gives backslashes. Compare with forward slashes. Only on
# Windows, because on POSIX a backslash is a normal file name character.
if os.sep == "\\":
    norm = norm.replace("\\", "/")

allowed = (
    "/.localdev/workflow/" in norm
    or norm.startswith(".localdev/workflow/")
    or norm == "docs/KNOWN_ISSUES.md"
    or norm.endswith("/docs/KNOWN_ISSUES.md")
)

if allowed:
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "permissionDecisionReason": "agentic-workflow-framework working path",
        }
    }))
'
