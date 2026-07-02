#!/usr/bin/env bash
# allow-workflow-paths.sh -- PreToolUse hook (plugin install path).
# Marketplace installs cannot pre-grant permission globs in ~/.claude/settings.json,
# so this hook auto-allows Write/Edit on the framework's working paths instead,
# mirroring exactly what install.sh grants:
#   .localdev/workflow/**  and  docs/KNOWN_ISSUES.md
# Any other path produces no output, leaving the normal permission flow intact.

set -euo pipefail

exec python3 -c '
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
