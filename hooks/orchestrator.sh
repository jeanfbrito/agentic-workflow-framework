#!/usr/bin/env bash
# Orchestrator — UserPromptSubmit reinforcement hook
# Performance: 1-2 forks on hot path (jq + grep), zero forks on skip path. ~5-15ms.
# Cost: injects ~25 tokens ONLY when the user prompt contains work verbs and
#       does NOT contain an opt-out phrase or framework slash command.
#
# The directive itself lives in ~/.claude/AGENTIC.md § Operating Mode. This
# hook is pure reinforcement against mid-session model drift.

set -u

input=$(cat)

# Extract prompt field if stdin is JSON (Claude Code hook event format).
# Fallback to raw stdin if jq is unavailable — grep over full JSON still
# works because JSON keys do not contain work verbs in their values.
if command -v jq >/dev/null 2>&1; then
  prompt=$(jq -r '.prompt // ""' <<<"$input" 2>/dev/null)
  # If jq failed or prompt is empty, fall back to raw input
  [ -z "$prompt" ] && prompt=$input
else
  prompt=$input
fi

# Bypass list — opt-outs and framework slash commands handle their own mode.
# Pure bash substring match, zero forks.
for bypass in \
  "off orchestrator" \
  "orchestrator off" \
  "do it yourself" \
  "/agentic" \
  "/handoff" \
  "/blocker" \
  "/known-issue" \
  "/init-agentic" \
  "/uninstall-agentic"; do
  [[ "$prompt" == *"$bypass"* ]] && exit 0
done

# Skip short / conversational prompts — heuristic, cheap.
[ ${#prompt} -lt 30 ] && exit 0

# Match work verbs (case-insensitive, with explicit non-alpha boundaries for
# portability across BSD and GNU grep). Single fork.
if printf '%s' "$prompt" | grep -Eiq '(^|[^a-zA-Z])(fix|implement|refactor|create|update|rename|migrate|build|patch|port|deploy|install|generate|rework|wire|scaffold|bootstrap|integrate|modify|rewrite|extend)[a-zA-Z]*([^a-zA-Z]|$)'; then
  echo "orchestrator: delegate implementation to subagents (builder-fast/builder-smart, finder, researcher, tester); edit files yourself only for trivial one-liners or files already in context. See AGENTIC.md § Operating Mode."
fi
