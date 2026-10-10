#!/usr/bin/env bash
# skill-review-nudge.sh -- SessionStart hook for the weekly skill review.
# Starts a background measurement when the last one is 7 or more days old,
# and points to an unreviewed report at most once per day. Advisory only:
# always exits 0 and never blocks the session.

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../skills/skill-review/scripts/skill_review.py"
[ -f "$SCRIPT" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
python3 "$SCRIPT" nudge 2>/dev/null || true
exit 0
