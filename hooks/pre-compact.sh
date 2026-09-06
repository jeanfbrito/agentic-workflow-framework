#!/usr/bin/env bash
# pre-compact.sh -- PreCompact hook: snapshot in-flight cards before the
# transcript is compacted, so the orchestrator can recover context on the
# other side instead of losing track of dispatched cards and re-dispatching
# builders that may still be running.
#
# Writes .localdev/workflow/_precompact-snapshot.md: timestamp, trigger
# (manual/auto from stdin JSON), verbatim copy of every open [doing]/
# [blocked] card from todo.md. session-scan.sh (SessionStart) picks the
# snapshot up on the next `compact`/`resume` source, injects a warning
# block, and deletes it; on `startup`/`clear` it deletes any stale
# snapshot silently.
#
# Never exits nonzero; silent no-op when .localdev/workflow/ is absent,
# todo.md is missing, there are no open [doing]/[blocked] cards, or stdin
# is missing/malformed.

set -uo pipefail

# Capture the hook's real stdin BEFORE handing off to python3 -- a heredoc
# on the python3 invocation below is used as the script SOURCE, which would
# otherwise consume/replace stdin and silently starve sys.stdin.read() of
# the piped JSON. Passing it through an env var keeps the heredoc (readable,
# no quoting gymnastics) while still delivering the real payload.
HOOK_STDIN_JSON="$(cat)"
export HOOK_STDIN_JSON

python3 <<'PYEOF' || true
import datetime
import json
import os
import re

WORKFLOW_DIR = ".localdev/workflow"


def main():
    # Defensive stdin parse -- missing/malformed stdin must never break the hook.
    try:
        raw = os.environ.get("HOOK_STDIN_JSON", "")
        payload = json.loads(raw) if raw.strip() else {}
    except Exception:
        payload = {}
    trigger = payload.get("trigger", "") if isinstance(payload, dict) else ""
    if trigger not in ("manual", "auto"):
        trigger = trigger or "unknown"

    if not os.path.isdir(WORKFLOW_DIR):
        return  # silent no-op -- no framework state in this repo

    todo_path = os.path.join(WORKFLOW_DIR, "todo.md")
    if not os.path.isfile(todo_path):
        return

    try:
        with open(todo_path) as fh:
            lines = fh.readlines()
    except Exception:
        return

    n = len(lines)
    i = 0
    card_blocks = []
    while i < n:
        if re.match(r"^## \[(doing|blocked)\]", lines[i]):
            j = i + 1
            while j < n and not lines[j].startswith("## "):
                j += 1
            card_blocks.append("".join(lines[i:j]).rstrip("\n"))
            i = j
        else:
            i += 1

    if not card_blocks:
        return  # nothing in-flight worth snapshotting

    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    body = (
        "# PreCompact snapshot\n\n"
        f"- Timestamp: {ts}\n"
        f"- Trigger: {trigger}\n\n"
        + "\n\n".join(card_blocks)
        + "\n"
    )
    try:
        with open(os.path.join(WORKFLOW_DIR, "_precompact-snapshot.md"), "w") as fh:
            fh.write(body)
    except Exception:
        pass


main()
PYEOF

exit 0
