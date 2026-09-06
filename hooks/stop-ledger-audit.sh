#!/usr/bin/env bash
# stop-ledger-audit.sh -- Stop hook: deterministic ledger hygiene checks.
#
# Diffs what the session actually touched (via the transcript JSONL) against
# .localdev/workflow/ ledger mtimes/content, and surfaces "ACTION REQUIRED"
# when discipline (done.md append, card close-out, blocker consistency)
# looks like it slipped. Turns doctrine into a check instead of a hope.
#
# Checks (pure stat/grep/parse, all against CWD's .localdev/workflow/):
#   1. >=3 non-ledger files written this session AND done.md is stale
#      (older than the session's first transcript timestamp, or absent)
#   2. todo.md has an open [doing] card AND todo.md itself was never
#      written/edited this session
#   3. blockers.md has entries with no matching [blocked] card in todo.md,
#      or vice versa
#
# Delivery: overwrites (never appends) .localdev/workflow/_audit-pending.md
# -- session-scan.sh (SessionStart) injects it into the next digest and
# deletes it. ALSO emits the same warnings same-turn via
# hookSpecificOutput.additionalContext (confirmed honored for Stop). Never
# uses decision:"block" -- hygiene warnings should not force continuation.
#
# Must be fast (<1s) and NEVER block the stop: always exits 0. Skips
# entirely when .localdev/workflow/ is absent, transcript_path is
# missing/unreadable, stop_hook_active is true (avoid loops), or the
# transcript is fully unparseable (schema drift/garbage -- no signal, no
# warning). Transcript JSONL schema is UNDOCUMENTED; parsed defensively,
# bad lines skipped individually.

set -uo pipefail

# Capture the hook's real stdin BEFORE handing off to python3 -- see
# session-scan.sh's header comment for why (heredoc-as-script-source would
# otherwise starve sys.stdin.read() of the piped JSON).
HOOK_STDIN_JSON="$(cat)"
export HOOK_STDIN_JSON

python3 <<'PYEOF' || true
import datetime
import json
import os
import re

WORKFLOW_DIR = ".localdev/workflow"


def parse_iso(ts):
    if ts.endswith("Z"):
        ts = ts[:-1] + "+00:00"
    return datetime.datetime.fromisoformat(ts).timestamp()


def scan_transcript(transcript_path):
    """Returns (written_files, todo_written, first_ts, parsed_any)."""
    written_files = set()
    todo_written = False
    first_ts = None
    parsed_any = False
    with open(transcript_path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            if not isinstance(obj, dict):
                continue
            parsed_any = True

            ts = obj.get("timestamp")
            if ts and first_ts is None:
                try:
                    parse_iso(ts)  # validate before committing
                    first_ts = ts
                except Exception:
                    pass

            msg = obj.get("message")
            if not isinstance(msg, dict):
                continue
            content = msg.get("content")
            if not isinstance(content, list):
                continue
            for item in content:
                if not isinstance(item, dict):
                    continue
                if item.get("type") != "tool_use":
                    continue
                if item.get("name") not in ("Write", "Edit"):
                    continue
                tool_input = item.get("input")
                if not isinstance(tool_input, dict):
                    continue
                fp = tool_input.get("file_path")
                if not fp or not isinstance(fp, str):
                    continue
                norm = os.path.normpath(fp)
                if "/.localdev/" in norm or norm.startswith(".localdev/"):
                    if norm.endswith("/todo.md") or norm == "todo.md":
                        todo_written = True
                    continue  # ledger writes don't count toward the file signal
                if norm.startswith("/private/tmp/") or "/private/tmp/" in norm:
                    continue  # scratchpad writes don't count either
                written_files.add(norm)

    return written_files, todo_written, first_ts, parsed_any


def main():
    try:
        raw = os.environ.get("HOOK_STDIN_JSON", "")
        payload = json.loads(raw) if raw.strip() else {}
    except Exception:
        payload = {}
    if not isinstance(payload, dict):
        payload = {}

    if payload.get("stop_hook_active"):
        return  # already continuing from a stop hook -- avoid loops

    if not os.path.isdir(WORKFLOW_DIR):
        return  # no framework state in this repo

    transcript_path = payload.get("transcript_path")
    if not transcript_path or not isinstance(transcript_path, str):
        return
    if not os.path.isfile(transcript_path):
        return

    try:
        written_files, todo_written, first_ts, parsed_any = scan_transcript(transcript_path)
    except Exception:
        return  # never hard-fail on schema drift / IO errors

    if not parsed_any:
        return  # transcript was fully unreadable -- no signal, no warning

    warnings = []

    # Check 1 -- >=3 non-ledger files written AND done.md stale.
    if len(written_files) >= 3:
        done_path = os.path.join(WORKFLOW_DIR, "done.md")
        done_mtime = None
        if os.path.isfile(done_path):
            try:
                done_mtime = os.path.getmtime(done_path)
            except Exception:
                done_mtime = None
        first_ts_epoch = None
        if first_ts:
            try:
                first_ts_epoch = parse_iso(first_ts)
            except Exception:
                first_ts_epoch = None
        stale = (done_mtime is None) or (
            first_ts_epoch is not None and done_mtime < first_ts_epoch
        )
        if stale:
            warnings.append(
                f"{len(written_files)} files changed but done.md has no new "
                "entry — append the completion entry or write a handoff"
            )

    # Check 2 -- [doing] card(s) left open, todo.md never touched this session.
    todo_path = os.path.join(WORKFLOW_DIR, "todo.md")
    doing_titles = []
    if os.path.isfile(todo_path):
        try:
            with open(todo_path) as fh:
                for raw_line in fh:
                    m = re.match(r"^## \[doing\]\s*(.*)", raw_line)
                    if m:
                        doing_titles.append(m.group(1).strip())
        except Exception:
            doing_titles = []
    if doing_titles and not todo_written:
        warnings.append(
            "card(s) left [doing]: " + ", ".join(doing_titles)
            + " — close to done.md, mark [blocked] with a blockers.md entry, or hand off"
        )

    # Check 3 -- blockers.md / todo.md [blocked] consistency, both directions.
    blockers_path = os.path.join(WORKFLOW_DIR, "blockers.md")
    has_blocker_entries = False
    if os.path.isfile(blockers_path):
        try:
            with open(blockers_path) as fh:
                for raw_line in fh:
                    if re.match(r"^## [0-9]{4}-", raw_line):
                        has_blocker_entries = True
                        break
        except Exception:
            has_blocker_entries = False
    has_blocked_card = False
    if os.path.isfile(todo_path):
        try:
            with open(todo_path) as fh:
                for raw_line in fh:
                    if re.match(r"^## \[blocked\]", raw_line):
                        has_blocked_card = True
                        break
        except Exception:
            has_blocked_card = False
    if has_blocker_entries and not has_blocked_card:
        warnings.append("blockers.md has entries but todo.md has no matching [blocked] card")
    elif has_blocked_card and not has_blocker_entries:
        warnings.append("todo.md has a [blocked] card but blockers.md has no entries")

    if not warnings:
        return  # nothing to report -- emit nothing, leave any absent file absent

    body = "ACTION REQUIRED\n\n" + "\n".join(f"- {w}" for w in warnings) + "\n"

    try:
        with open(os.path.join(WORKFLOW_DIR, "_audit-pending.md"), "w") as fh:
            fh.write(body)
    except Exception:
        pass

    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "Stop",
            "additionalContext": body.rstrip("\n"),
        }
    }))


try:
    main()
except Exception:
    pass
PYEOF

exit 0
