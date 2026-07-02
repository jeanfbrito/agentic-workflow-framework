#!/usr/bin/env bash
# inject-agentic-context.sh -- SessionStart hook (plugin install path).
# Marketplace installs cannot add the @AGENTIC.md import to ~/.claude/CLAUDE.md,
# so this hook injects AGENTIC.md into session context via stdout instead.
# No-ops when the shell installer's import is already present -- otherwise the
# framework conventions would load twice.

set -euo pipefail

if grep -qF '@AGENTIC.md' "$HOME/.claude/CLAUDE.md" 2>/dev/null; then
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cat "$SCRIPT_DIR/../AGENTIC.md"
