#!/usr/bin/env bash
# Test-run advisor — PreToolUse hook on Bash.
#
# A test suite or a type check that runs in the foreground blocks the main
# thread. In one session the main thread ran the same client suite three times
# in a row (one run per batch of cherry-picks), and it waited for each run.
# This hook advises: run long checks in the background, scope them to the
# changed files, and reuse a PASS on the same commit. It never blocks.
#
# Skips: subagent calls (agent_id in the payload), background runs, commands
# that are not test or type-check runs. Rate limit: one advice per session
# every 10 minutes.

set -u

input=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

[ -n "$(jq -r '.agent_id // empty' <<<"$input" 2>/dev/null)" ] && exit 0
[ "$(jq -r '.tool_input.run_in_background // false' <<<"$input" 2>/dev/null)" = "true" ] && exit 0

cmd=$(jq -r '.tool_input.command // ""' <<<"$input" 2>/dev/null)
printf '%s' "$cmd" | grep -Eq '(^|[;&|( ])(npx |bunx |yarn |pnpm exec )?(jest|vitest|pytest)( |$)|(yarn|npm|pnpm|bun) (run )?test( |$)|playwright test|node --test|go test|cargo test|tsc( [^|;&]*)? --noEmit' || exit 0

session=$(jq -r '.session_id // "none"' <<<"$input" 2>/dev/null)
state_dir="${AGENTIC_STATE_DIR:-${TMPDIR:-/tmp}/agentic-test-run-advisor}"
mkdir -p "$state_dir" 2>/dev/null || exit 0
stamp="$state_dir/$session"
now=$(date +%s)
if [ -f "$stamp" ]; then
  last=$(cat "$stamp" 2>/dev/null || echo 0)
  [ $((now - last)) -lt 600 ] && exit 0
fi
echo "$now" >"$stamp"

msg="test-run: this test or type-check run is in the foreground. If it can take more than a minute, run it with run_in_background or give it to a watcher, and continue other work. Run only the specs of the changed files and the type check. Run the full suite only for a broad change (shared module, dependency, config, many merged branches) or once as the last gate before a push. Integrate all ready work first, then check once. A PASS on the same commit with the same command is still valid. See AGENTIC.md § Completion and Evidence."
jq -n --arg m "$msg" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'
exit 0
