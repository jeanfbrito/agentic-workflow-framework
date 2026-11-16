#!/usr/bin/env bash
# Struggle advisor — PostToolUseFailure hook on Bash.
#
# A main thread that retries commands by hand can loop for a long time. A small
# task tool (a probe, a repro script, a parser) often ends the loop: the agent
# observes through the tool instead of through each retry. This hook counts
# Bash failures per session. At the third failure in 15 minutes it advises the
# agent to build a task tool (AGENTIC.md § Completion and Evidence, "Build the
# tool when you struggle"). It never blocks.
#
# Skips: subagent calls (agent_id in the payload), and failures with no output
# after the "Exit code N" line (a grep with no match, a `test` that is false).
# Rate limit: one advice per session every 30 minutes.

set -u

input=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

[ -n "$(jq -r '.agent_id // empty' <<<"$input" 2>/dev/null)" ] && exit 0

err=$(jq -r '.error // ""' <<<"$input" 2>/dev/null)
detail=$(printf '%s\n' "$err" | sed '1{/^Exit code [0-9]*$/d;}' | tr -d '[:space:]')
[ -z "$detail" ] && exit 0

session=$(jq -r '.session_id // "none"' <<<"$input" 2>/dev/null)
state_dir="${AGENTIC_STATE_DIR:-${TMPDIR:-/tmp}/agentic-struggle-advisor}"
mkdir -p "$state_dir" 2>/dev/null || exit 0
fails="$state_dir/$session.fails"
stamp="$state_dir/$session.advised"
now=$(date +%s)
window=900

recent=$( { [ -f "$fails" ] && cat "$fails"; echo "$now"; } | awk -v n="$now" -v w="$window" '$1 > n - w')
printf '%s\n' "$recent" >"$fails"
[ "$(printf '%s\n' "$recent" | wc -l | tr -d ' ')" -lt 3 ] && exit 0

if [ -f "$stamp" ]; then
  last=$(cat "$stamp" 2>/dev/null || echo 0)
  [ $((now - last)) -lt 1800 ] && exit 0
fi
echo "$now" >"$stamp"

msg="struggle: three commands failed in the last 15 minutes. Do not retry by hand again. If you repeat the same observation (read a log, decode a format, check a page, compare an output), write a small task tool in the scratchpad: a probe, a repro script, a parser, or a diff check. Prove it on one case with a known answer, then use it. If two approaches failed, write down the premise they share and test it first. See AGENTIC.md § Completion and Evidence."
jq -n --arg m "$msg" '{hookSpecificOutput: {hookEventName: "PostToolUseFailure", additionalContext: $m}}'
exit 0
