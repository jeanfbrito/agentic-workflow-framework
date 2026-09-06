#!/usr/bin/env bash
# session-scan.sh -- SessionStart hook: budgeted, value-ordered digest of
# .localdev/workflow/ ledger state.
#
# Replaces the old inline shell one-liner (which only printed bare file
# *pointers*) with a real digest built from stdin JSON + the ledger files
# themselves, packed under a fixed char budget so the orchestrator never
# has to re-read the files just to know what's pending.
#
# Value order (highest first, greedy pack -- an oversized item is skipped,
# smaller ones after it still get a chance to fit):
#   0. PreCompact recovery warning (only when `source` is compact/resume and
#      a snapshot from hooks/pre-compact.sh exists and is <24h old) --
#      in-flight [doing]/[blocked] card titles from before the compaction,
#      snapshot deleted after injection
#   1. pending audit file (.localdev/workflow/_audit-pending.md), verbatim,
#      then deleted (regardless of whether it fit -- an oversized audit
#      file must not recreate itself forever)
#   2. active blocker H2 titles
#   3. open [todo]/[doing]/[blocked] card titles + their Attempts line
#   4. handoff filenames + age (stale >7d warning kept)
#   5. "agentic: armed" -- only when nothing else was printed
#
# On `startup`/`clear`, any stale snapshot is deleted silently (no
# injection) -- a snapshot only matters right after the compaction/resume
# it was written for.
#
# Never exits nonzero; silent no-op when .localdev/workflow/ is absent or
# stdin is missing/malformed. Output channel is the documented SessionStart
# context field (hookSpecificOutput.additionalContext).

set -uo pipefail

# Capture the hook's real stdin BEFORE handing off to python3 -- a heredoc
# on the python3 invocation below is used as the script SOURCE, which would
# otherwise consume/replace stdin and silently starve sys.stdin.read() of
# the piped JSON. Passing it through an env var keeps the heredoc (readable,
# no quoting gymnastics) while still delivering the real payload.
HOOK_STDIN_JSON="$(cat)"
export HOOK_STDIN_JSON

python3 <<'PYEOF' || true
import json
import os
import re
import time

BUDGET = 4000     # ~1k tokens -- keep the digest small enough to be free
LINE_CLIP = 140    # clip any single title/status line to this many chars

WORKFLOW_DIR = ".localdev/workflow"


def clip(line):
    line = line.rstrip("\n")
    return line if len(line) <= LINE_CLIP else line[: LINE_CLIP - 1] + "…"


def main():
    # Defensive stdin parse -- missing/malformed stdin must never break the hook.
    try:
        raw = os.environ.get("HOOK_STDIN_JSON", "")
        payload = json.loads(raw) if raw.strip() else {}
    except Exception:
        payload = {}
    source = payload.get("source", "") if isinstance(payload, dict) else ""

    if not os.path.isdir(WORKFLOW_DIR):
        return  # silent no-op -- no framework state in this repo

    blocks = []
    used = 0
    dropped = 0

    def add(text_lines):
        """Try to add an already-formatted list of lines as one atomic
        block. Returns True if it fit; a block that doesn't fit is
        skipped (not truncated) so smaller later items still get a chance."""
        nonlocal used, dropped
        if not text_lines:
            return True
        block = "\n".join(text_lines) + "\n"
        if used + len(block) > BUDGET:
            dropped += 1
            return False
        blocks.append(block)
        used += len(block)
        return True

    # 0. PreCompact recovery warning -- only on compact/resume with a fresh
    #    (<24h) snapshot; startup/clear just clean up a stale snapshot.
    snapshot_path = os.path.join(WORKFLOW_DIR, "_precompact-snapshot.md")
    if os.path.isfile(snapshot_path):
        if source in ("compact", "resume"):
            try:
                age_seconds = time.time() - os.path.getmtime(snapshot_path)
            except Exception:
                age_seconds = None
            if age_seconds is not None and age_seconds < 86400:
                try:
                    with open(snapshot_path) as fh:
                        snap_lines = fh.readlines()
                except Exception:
                    snap_lines = []
                titles = []
                for raw_line in snap_lines:
                    m = re.match(r"^## \[(doing|blocked)\]\s*(.*)", raw_line)
                    if m:
                        titles.append(clip(f"   [{m.group(1)}] {m.group(2).strip()}"))
                # Not clipped -- this is the fixed warning sentence, not a
                # title, and truncating it would drop the actual instruction.
                warn_block = [
                    "⚠️ Context was compacted/resumed mid-session. "
                    "In-flight cards below — do NOT re-dispatch builders that "
                    "may still be running; check TaskList/ListAgents first."
                ] + titles
                add(warn_block)
            try:
                os.remove(snapshot_path)
            except Exception:
                pass
        elif source in ("startup", "clear"):
            try:
                os.remove(snapshot_path)
            except Exception:
                pass

    # 1. Pending audit file -- verbatim (not clipped), then always deleted.
    audit_path = os.path.join(WORKFLOW_DIR, "_audit-pending.md")
    if os.path.isfile(audit_path):
        try:
            with open(audit_path) as fh:
                audit_text = fh.read().rstrip("\n")
        except Exception:
            audit_text = ""
        if audit_text:
            add(audit_text.split("\n"))
        try:
            os.remove(audit_path)
        except Exception:
            pass

    # 2. Active blocker H2 titles.
    blockers_path = os.path.join(WORKFLOW_DIR, "blockers.md")
    if os.path.isfile(blockers_path):
        try:
            with open(blockers_path) as fh:
                blocker_lines = fh.readlines()
        except Exception:
            blocker_lines = []
        for raw_line in blocker_lines:
            if re.match(r"^## [0-9]{4}-", raw_line):
                title = raw_line.rstrip("\n")[3:]
                add([clip(f"⚠️  Active blocker: {title}")])

    # 3. Open card titles + Attempts line.
    todo_path = os.path.join(WORKFLOW_DIR, "todo.md")
    if os.path.isfile(todo_path):
        try:
            with open(todo_path) as fh:
                todo_lines = fh.readlines()
        except Exception:
            todo_lines = []
        n = len(todo_lines)
        i = 0
        while i < n:
            m = re.match(r"^## \[(todo|doing|blocked)\]\s*(.*)", todo_lines[i])
            if m:
                status, title = m.group(1), m.group(2).strip()
                card_lines = [clip(f"\U0001F4CB [{status}] {title}")]
                j = i + 1
                while j < n and not todo_lines[j].startswith("## "):
                    am = re.match(r"^-\s*Attempts:\s*(.*)", todo_lines[j])
                    if am:
                        card_lines.append(clip(f"   Attempts: {am.group(1).strip()}"))
                        break
                    j += 1
                add(card_lines)
            i += 1

    # 4. Handoffs -- filenames + age, stale >7d warning kept.
    handoffs_dir = os.path.join(WORKFLOW_DIR, "handoffs")
    if os.path.isdir(handoffs_dir):
        try:
            names = sorted(os.listdir(handoffs_dir))
        except Exception:
            names = []
        now = time.time()
        for name in names:
            if not name.endswith(".md"):
                continue
            fpath = os.path.join(handoffs_dir, name)
            try:
                mtime = os.path.getmtime(fpath)
            except Exception:
                mtime = now
            age_days = int((now - mtime) // 86400)
            if age_days > 7:
                add([clip(
                    f"\U0001F4CB Open handoff: {name} (age: {age_days}d) "
                    "— stale, resume or absorb into done.md"
                )])
            else:
                add([clip(f"\U0001F4CB Open handoff: {name} (age: {age_days}d)")])

    # 5. Armed marker -- only when nothing else was printed.
    if not blocks:
        add(["✓ agentic: armed"])

    if dropped:
        blocks.append(f"…digest truncated ({dropped} item(s) dropped)\n")

    digest = "".join(blocks).rstrip("\n")
    if not digest:
        return

    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": digest,
        }
    }))


main()
PYEOF

exit 0
