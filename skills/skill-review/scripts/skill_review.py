#!/usr/bin/env python3
"""Weekly skill review: measure skill use and wiki habits from local sessions.

Subcommands:
  config    Show or set the personal config (wiki folder, proven-skills repo).
  measure   Scan recent Claude Code sessions and write the weekly report.
  nudge     SessionStart helper: start a stale measurement, point to a new report.
  reviewed  Mark the latest report as reviewed, so the nudge stops.

Everything runs locally with the Python 3.9+ standard library. Session
transcripts never leave the machine. The report holds counts, skill names and
short session labels, not transcript text.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

CLAUDE_HOME = Path(os.environ.get("CLAUDE_CONFIG_DIR", "~/.claude")).expanduser()
CONFIG_PATH = Path(os.environ.get("AGENTIC_CONFIG", str(CLAUDE_HOME / "agentic-config.json"))).expanduser()
STATE_DIR = CLAUDE_HOME / "agentic-state" / "skill-review"
FRAMEWORK_MANIFEST = CLAUDE_HOME / "skills" / ".agentic-framework-skills"

DEFAULT_CONFIG = {
    "wiki_dir": None,
    "reports_subdir": "Skill Reviews",
    "proven_skills_dir": None,
    "measure_every_days": 7,
    "wiki_ignore_subdirs": [],
}

# Claude Code built-in commands and bundled skills. They cannot be removed,
# so the report leaves them out.
BUILTIN = {
    "add-dir", "agents", "artifact-capabilities", "artifact-design", "artifact-diagramming",
    "bug", "claude-api", "claude-in-chrome", "clear", "compact", "config", "context", "cost",
    "doctor", "effort", "exit", "export", "fast", "fewer-permission-prompts", "goal", "help",
    "hooks", "ide", "init", "insights", "keybindings-help", "login", "logout", "loop", "mcp",
    "memory", "model", "permissions", "plugin", "plugin-authoring", "pr-comments",
    "release-notes", "reload-plugins", "resume", "review", "rewind", "run", "schedule",
    "security-review", "simplify", "status", "statusline", "terminal-setup", "todos",
    "update-config", "upgrade", "usage", "vim", "workflow-authoring",
}

MAX_FILE_BYTES = 16 * 1024 * 1024
COMMAND_NAME_RE = re.compile(r"<command-name>/([A-Za-z0-9_:.-]+)</command-name>")
EDIT_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit"}
WIKI_TOOL_RE = re.compile(r"obsidian_(save_note|update_note|capture|replace_text)")
# A session that records one of these found something new. If it wrote no
# wiki page, the report counts it as a missed wiki.
LESSON_TOOL_RE = re.compile(r"mm_write|mm_promote")
LESSON_SKILLS = {"learn", "postmortem", "known-issue"}
LESSON_FILE_RE = re.compile(r"(/memory/[^/]+\.md$|/lessons\.md$|/KNOWN_ISSUES\.md$|/findings\.md$)")


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

def load_config():
    cfg = dict(DEFAULT_CONFIG)
    try:
        cfg.update(json.loads(CONFIG_PATH.read_text()))
    except (OSError, ValueError):
        pass
    if os.environ.get("AGENTIC_WIKI_DIR"):
        cfg["wiki_dir"] = os.environ["AGENTIC_WIKI_DIR"]
    return cfg


def save_config(cfg):
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    stored = {k: v for k, v in cfg.items() if v is not None}
    CONFIG_PATH.write_text(json.dumps(stored, indent=2) + "\n")


def expand(path):
    return Path(path).expanduser().resolve() if path else None


def cmd_config(args):
    cfg = load_config()
    changed = False
    for key in ("wiki_dir", "proven_skills_dir"):
        value = getattr(args, key)
        if value is None:
            continue
        if value == "":
            cfg[key] = None
        else:
            path = Path(value).expanduser()
            if not path.is_dir():
                print(f"ERROR: {key}: {path} is not a directory.", file=sys.stderr)
                return 1
            cfg[key] = str(path.resolve())
        changed = True
    if args.wiki_ignore is not None:
        cfg["wiki_ignore_subdirs"] = [d for d in args.wiki_ignore.split(",") if d]
        changed = True
    if args.reports_subdir:
        cfg["reports_subdir"] = args.reports_subdir
        changed = True
    if changed:
        save_config(cfg)
    print(json.dumps({"config_file": str(CONFIG_PATH), **cfg}, indent=2))
    return 0


# ---------------------------------------------------------------------------
# Skill inventory
# ---------------------------------------------------------------------------

def read_description(skill_md):
    try:
        text = skill_md.read_text(errors="replace")[:4000]
    except OSError:
        return ""
    m = re.search(r"^description:\s*(.+)$", text, re.MULTILINE)
    return m.group(1).strip().strip("\"'")[:240] if m else ""


def skill_dirs(root):
    """Yield (name, SKILL.md) for <root>/<name>/SKILL.md and one nested level."""
    if not root.is_dir():
        return
    for pattern in ("*/SKILL.md", "*/*/SKILL.md"):
        for skill_md in sorted(root.glob(pattern)):
            yield skill_md.parent.name, skill_md


def framework_skill_names():
    try:
        return {line.strip() for line in FRAMEWORK_MANIFEST.read_text().splitlines() if line.strip()}
    except OSError:
        return {"agentic-workflow", "personal-engineering-rules", "skill-review",
                "agentic", "blocker", "handoff", "init-agentic", "known-issue", "qq"}


def global_skills(cfg):
    """Classify ~/.claude/skills entries into framework, proven, linked and trial."""
    proven = expand(cfg.get("proven_skills_dir"))
    framework = framework_skill_names()
    skills = {}
    for name, skill_md in skill_dirs(CLAUDE_HOME / "skills"):
        top = CLAUDE_HOME / "skills" / skill_md.relative_to(CLAUDE_HOME / "skills").parts[0]
        if top.name.startswith("."):
            continue
        target = top.resolve()
        if top.name in framework:
            stage = "framework"
        elif top.is_symlink() and proven and (target == proven or proven in target.parents):
            stage = "proven"
        elif top.is_symlink():
            stage = "linked"
        else:
            stage = "trial"
        skills[name] = {
            "name": name,
            "stage": stage,
            "path": str(top),
            "target": str(target) if top.is_symlink() else None,
            "description": read_description(skill_md),
        }
    return skills


def plugin_skills():
    """Skills from enabled plugins, newest cached version of each plugin."""
    try:
        settings = json.loads((CLAUDE_HOME / "settings.json").read_text())
    except (OSError, ValueError):
        settings = {}
    enabled = {k.split("@")[0] for k, v in (settings.get("enabledPlugins") or {}).items() if v}
    skills = {}
    cache = CLAUDE_HOME / "plugins" / "cache"
    for plugin_dir in sorted(cache.glob("*/*")):
        plugin = plugin_dir.name
        if plugin not in enabled or not plugin_dir.is_dir():
            continue
        versions = [v for v in plugin_dir.iterdir()
                    if (v / "skills").is_dir() or (v / "commands").is_dir() or (v / "SKILL.md").is_file()]
        if not versions:
            continue
        newest = max(versions, key=lambda v: v.stat().st_mtime)
        entries = [(name, md) for name, md in skill_dirs(newest / "skills")]
        if (newest / "SKILL.md").is_file():
            entries.append((plugin, newest / "SKILL.md"))
        entries += [(md.stem, md) for md in sorted((newest / "commands").glob("*.md"))]
        for name, skill_md in entries:
            full = f"{plugin}:{name}"
            skills.setdefault(full, {
                "name": full,
                "stage": "plugin",
                "plugin": plugin,
                "path": str(skill_md),
                "description": read_description(skill_md),
            })
    return skills


def global_commands():
    """Slash commands in ~/.claude/commands/*.md."""
    framework = framework_skill_names()
    commands = {}
    for md in sorted((CLAUDE_HOME / "commands").glob("*.md")):
        target = md.resolve()
        # A command that links into a skill folder belongs to that skill's owner.
        if md.is_symlink() and "/skills/" in str(target):
            continue
        commands[f"/{md.stem}"] = {
            "name": md.stem,
            "stage": "framework" if md.stem in framework else "command",
            "path": str(md),
            "description": read_description(md),
        }
    return commands


def project_root(cwd):
    if not cwd:
        return None
    path = Path(cwd)
    for candidate in (path, *path.parents):
        if (candidate / ".git").exists():
            return candidate
    return None


def project_skills(roots):
    skills = {}
    for root in sorted(roots):
        for name, skill_md in skill_dirs(root / ".claude" / "skills"):
            key = f"{root.name}/{name}"
            skills.setdefault(key, {
                "name": name,
                "key": key,
                "stage": "project",
                "project": root.name,
                "path": str(skill_md.parent),
                "description": read_description(skill_md),
            })
    return skills


# ---------------------------------------------------------------------------
# Session scan
# ---------------------------------------------------------------------------

def session_files(since):
    projects = CLAUDE_HOME / "projects"
    files = list(projects.glob("*/*.jsonl")) + list(projects.glob("*/*/subagents/*.jsonl"))
    out = []
    for path in files:
        try:
            if datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc) >= since:
                out.append(path)
        except OSError:
            continue
    return out


def parse_ts(value):
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (AttributeError, ValueError):
        return None


def under(path_str, root):
    if not path_str or not root:
        return False
    try:
        path = Path(path_str).expanduser().resolve()
    except (OSError, RuntimeError):
        return False
    return path == root or root in path.parents


def scan_session(path, since, wiki_root, ignored_roots):
    """Return the facts one transcript contributes inside the window."""
    try:
        raw = path.read_text(errors="replace")[:MAX_FILE_BYTES]
    except OSError:
        return None
    facts = {
        "file": str(path),
        "subagent": "/subagents/" in str(path),
        "cwd": None,
        "first_prompt": None,
        "invocations": [],      # (name, timestamp)
        "skill_edits": set(),   # SKILL.md paths written
        "wiki_writes": set(),
        "lesson_signals": set(),
        "last_ts": None,
    }
    for line in raw.splitlines():
        try:
            obj = json.loads(line)
        except ValueError:
            continue
        ts = parse_ts(obj.get("timestamp"))
        if ts is None or ts < since:
            continue
        facts["last_ts"] = ts
        facts["cwd"] = facts["cwd"] or obj.get("cwd")
        message = obj.get("message")
        if obj.get("type") not in ("user", "assistant") or not isinstance(message, dict):
            continue
        content = message.get("content")
        blocks = content if isinstance(content, list) else [{"type": "text", "text": content}]
        for block in blocks:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "text" and obj.get("type") == "user":
                text = block.get("text") or ""
                if not isinstance(text, str):
                    continue
                for name in COMMAND_NAME_RE.findall(text):
                    facts["invocations"].append((name, ts))
                if facts["first_prompt"] is None and text.strip() and not text.lstrip().startswith("<"):
                    facts["first_prompt"] = " ".join(text.split())[:90]
            elif block.get("type") == "tool_use":
                name = str(block.get("name") or "")
                args = block.get("input") if isinstance(block.get("input"), dict) else {}
                if name == "Skill" and args.get("skill"):
                    skill = str(args["skill"])
                    facts["invocations"].append((skill, ts))
                    if skill.split(":")[-1] in LESSON_SKILLS:
                        facts["lesson_signals"].add(f"/{skill}")
                elif name in EDIT_TOOLS:
                    target = str(args.get("file_path") or args.get("notebook_path") or "")
                    if target.endswith("/SKILL.md"):
                        facts["skill_edits"].add(target)
                    if under(target, wiki_root) and not any(under(target, r) for r in ignored_roots):
                        facts["wiki_writes"].add(target)
                    if LESSON_FILE_RE.search(target) and not under(target, wiki_root):
                        facts["lesson_signals"].add(Path(target).name)
                elif WIKI_TOOL_RE.search(name):
                    facts["wiki_writes"].add(f"{name}:{args.get('path') or args.get('title') or ''}")
                elif LESSON_TOOL_RE.search(name):
                    facts["lesson_signals"].add(name.split("__")[-1])
    if facts["last_ts"] is None:
        return None
    return facts


def match_invocation(raw_name, skills_by_name):
    """Map an invoked name to inventory keys. Plugin skills use 'plugin:skill'."""
    if raw_name in skills_by_name:
        return skills_by_name[raw_name]
    short = raw_name.split(":")[-1]
    return skills_by_name.get(short, [])


# ---------------------------------------------------------------------------
# Measure
# ---------------------------------------------------------------------------

def iso_week(ts):
    year, week, _ = ts.isocalendar()
    return f"{year}-W{week:02d}"


def measure(cfg, days, long_days):
    now = datetime.now(timezone.utc)
    short_since = now - timedelta(days=days)
    long_since = now - timedelta(days=long_days)
    wiki_root = expand(cfg.get("wiki_dir"))
    ignored_roots = []
    if wiki_root:
        ignored_roots = [wiki_root / d for d in [cfg["reports_subdir"], *(cfg.get("wiki_ignore_subdirs") or [])]]

    sessions = []
    for path in session_files(long_since):
        facts = scan_session(path, long_since, wiki_root, ignored_roots)
        if facts:
            sessions.append(facts)

    roots = {r for r in (project_root(s["cwd"]) for s in sessions) if r}
    inventory = {}
    inventory.update(global_commands())
    inventory.update(global_skills(cfg))
    inventory.update(plugin_skills())
    inventory.update(project_skills(roots))

    by_name = {}
    for key, skill in inventory.items():
        by_name.setdefault(skill["name"], []).append(key)
        if skill["stage"] == "plugin":
            by_name.setdefault(key.split(":")[-1], []).append(key)

    for skill in inventory.values():
        skill.update({"uses_short": 0, "uses_long": 0, "weeks": set(), "projects": set(), "last_used": None})

    unknown = {}
    for s in sessions:
        root = project_root(s["cwd"])
        for raw_name, ts in s["invocations"]:
            keys = match_invocation(raw_name, by_name)
            # A project skill counts only inside its own project.
            keys = [k for k in keys if inventory[k]["stage"] != "project"
                    or (root and inventory[k]["project"] == root.name)]
            if not keys:
                if raw_name.split(":")[-1] in BUILTIN:
                    continue
                unknown[raw_name] = unknown.get(raw_name, 0) + 1
                continue
            for key in keys[:1]:
                skill = inventory[key]
                skill["uses_long"] += 1
                if ts >= short_since:
                    skill["uses_short"] += 1
                skill["weeks"].add(iso_week(ts))
                if root:
                    skill["projects"].add(root.name)
                if not skill["last_used"] or ts.isoformat() > skill["last_used"]:
                    skill["last_used"] = ts.date().isoformat()

    week_sessions = [s for s in sessions if s["last_ts"] >= short_since]
    lesson_sessions = [s for s in week_sessions if s["lesson_signals"]]
    missed = [s for s in lesson_sessions if not s["wiki_writes"]]
    wiki_pages = sorted({w for s in week_sessions for w in s["wiki_writes"]})
    skill_edits = sorted({e for s in week_sessions for e in s["skill_edits"]})

    def label(s):
        root = project_root(s["cwd"])
        return {
            "project": root.name if root else (s["cwd"] or "?"),
            "date": s["last_ts"].date().isoformat(),
            "subagent": s["subagent"],
            "prompt": s["first_prompt"] or "",
            "signals": sorted(s["lesson_signals"]),
        }

    skills_out = []
    for key, skill in sorted(inventory.items()):
        skills_out.append({
            **{k: v for k, v in skill.items() if k not in ("weeks", "projects")},
            "key": key,
            "weeks": sorted(skill["weeks"]),
            "projects": sorted(skill["projects"]),
        })

    return {
        "generated_at": now.isoformat(timespec="seconds"),
        "window_days": days,
        "long_window_days": long_days,
        "config": {k: cfg.get(k) for k in DEFAULT_CONFIG},
        "sessions": {
            "scanned_long": len(sessions),
            "in_week": len(week_sessions),
            "in_week_main": sum(1 for s in week_sessions if not s["subagent"]),
        },
        "wiki": {
            "configured": bool(wiki_root),
            "pages_written": len(wiki_pages),
            "page_paths": wiki_pages[:50],
            "sessions_with_new_findings": len(lesson_sessions),
            "missed": [label(s) for s in missed][:30],
            "missed_count": len(missed),
        },
        "skill_edits": skill_edits,
        "skills": skills_out,
        "unknown_invocations": dict(sorted(unknown.items(), key=lambda kv: -kv[1])[:20]),
    }


STAGE_ORDER = ["project", "trial", "proven", "linked", "command", "framework", "plugin"]
STAGE_HELP = {
    "project": "lives in one repo's `.claude/skills/`; counts only in that repo",
    "trial": "general skill on trial: a plain folder in `~/.claude/skills/`",
    "proven": "promoted: a symlink into the proven-skills repo",
    "linked": "a symlink into another repo (a skills installer or another tool)",
    "command": "a slash command in `~/.claude/commands/`",
    "framework": "installed by agentic-workflow-framework",
    "plugin": "comes from an enabled Claude Code plugin",
}


def render_markdown(report, previous):
    today = report["generated_at"][:10]
    wiki = report["wiki"]
    skills = report["skills"]
    unused = [s for s in skills if s["uses_long"] == 0]
    used_week = [s for s in skills if s["uses_short"] > 0]

    def delta(key_path, value):
        if not previous:
            return ""
        prev = previous
        for k in key_path:
            prev = (prev or {}).get(k)
        if not isinstance(prev, int):
            return ""
        diff = value - prev
        return f" ({'+' if diff >= 0 else ''}{diff} vs last report)"

    lines = [
        "---",
        "type: review",
        f"date: {today}",
        "tags:",
        "  - skill-review",
        "  - agent-tooling",
        "ai-first: true",
        "---",
        "",
        f"# Skill Review {today}",
        "",
        "## For future agent",
        "",
        f"Weekly measurement of Claude Code skill use and wiki habits, generated {today} by the "
        "agentic-workflow-framework `skill-review` script from local session transcripts. "
        f"It covers the last {report['window_days']} days, with skill use also counted over "
        f"{report['long_window_days']} days. The Decisions section is filled by the review step "
        "and stays empty until the user approves it.",
        "",
        "## Numbers",
        "",
        f"- Sessions in the week: {report['sessions']['in_week_main']} main, "
        f"{report['sessions']['in_week'] - report['sessions']['in_week_main']} subagent.",
        f"- Skills invoked this week: {len(used_week)} of {len(skills)} installed.",
        f"- Skills with no use in {report['long_window_days']} days: {len(unused)}"
        f"{delta(['unused_count'], len(unused))}.",
        f"- Wiki pages written: {wiki['pages_written']}{delta(['wiki', 'pages_written'], wiki['pages_written'])}.",
        f"- Sessions that recorded a new finding: {wiki['sessions_with_new_findings']}.",
        f"- Of those, sessions with no wiki page (missed wiki): {wiki['missed_count']}"
        f"{delta(['wiki', 'missed_count'], wiki['missed_count'])}.",
        f"- SKILL.md files created or changed: {len(report['skill_edits'])}.",
        "",
        "## How to read this",
        "",
        "- **Invoked** means a real `Skill` tool call or a typed `/name` command. A skill whose "
        "name only appears in text does not count, because that is the failure this report finds.",
        "- **Missed wiki** means the session saved a lesson (memory, lessons file, known issue, "
        "`/learn`, `/postmortem`) but wrote no page in the wiki folder. Each one is a finding "
        "that the user did not get to read.",
        "- A rare skill is not a useless skill. A release skill runs once per release. "
        "Judge each skill against its expected rhythm, not against the weekly count.",
        "- Stages:",
    ]
    for stage in STAGE_ORDER:
        lines.append(f"  - `{stage}`: {STAGE_HELP[stage]}.")
    lines += ["", "## Skills by stage", ""]
    for stage in STAGE_ORDER:
        group = [s for s in skills if s["stage"] == stage]
        if not group:
            continue
        used = [s for s in group if s["uses_long"]]
        idle = [s for s in group if not s["uses_long"]]
        lines += [f"### {stage} ({len(used)} used, {len(idle)} idle)", ""]
        if used:
            lines += [f"| Skill | Week | {report['long_window_days']}d | Weeks used | Last used |",
                      "| --- | ---: | ---: | ---: | --- |"]
            for s in sorted(used, key=lambda s: (-s["uses_long"], s["key"])):
                lines.append(f"| `{s['key']}` | {s['uses_short']} | {s['uses_long']} | "
                             f"{len(s['weeks'])} | {s['last_used']} |")
            lines.append("")
        if idle:
            lines += [f"Idle for {report['long_window_days']} days: "
                      + ", ".join(f"`{s['key']}`" for s in sorted(idle, key=lambda s: s["key"])), ""]
    if wiki["missed"]:
        lines += ["## Missed wikis", ""]
        for m in wiki["missed"]:
            who = " (subagent)" if m["subagent"] else ""
            lines.append(f"- {m['date']} `{m['project']}`{who}: {', '.join(m['signals'])}"
                         + (f" - \"{m['prompt']}\"" if m["prompt"] else ""))
        lines.append("")
    if report["skill_edits"]:
        lines += ["## Skills created or changed", ""] + [f"- `{p}`" for p in report["skill_edits"]] + [""]
    if report["unknown_invocations"]:
        lines += ["## Invoked names not in the inventory", "",
                  "Built-in commands, removed skills, or skills from a repo with no session this window.", ""]
        lines += [f"- `{k}`: {v}" for k, v in report["unknown_invocations"].items()] + [""]
    lines += ["## Decisions", "", "_Pending review. Run `/skill-review` in a session._", ""]
    return "\n".join(lines)


def latest_state():
    try:
        return json.loads((STATE_DIR / "latest.json").read_text())
    except (OSError, ValueError):
        return {}


def cmd_measure(args):
    cfg = load_config()
    report = measure(cfg, args.days, args.long_days)
    report["unused_count"] = sum(1 for s in report["skills"] if s["uses_long"] == 0)
    previous = None
    history = STATE_DIR / "history.jsonl"
    try:
        previous = json.loads(history.read_text().splitlines()[-1])
    except (OSError, ValueError, IndexError):
        pass

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    report_json = STATE_DIR / f"report-{report['generated_at'][:10]}.json"
    report_json.write_text(json.dumps(report, indent=2, default=list))

    markdown = render_markdown(report, previous)
    wiki_root = expand(cfg.get("wiki_dir"))
    if wiki_root and not args.no_wiki:
        out_dir = wiki_root / cfg["reports_subdir"]
    else:
        out_dir = STATE_DIR
    out_dir.mkdir(parents=True, exist_ok=True)
    report_md = out_dir / f"{report['generated_at'][:10]} - Skill Review.md"
    if report_md.exists() and "_Pending review." not in report_md.read_text():
        report_md = out_dir / f"{report['generated_at'][:10]} - Skill Review (remeasured).md"
    report_md.write_text(markdown)

    summary = {
        "generated_at": report["generated_at"],
        "unused_count": report["unused_count"],
        "wiki": {k: report["wiki"][k] for k in ("pages_written", "missed_count", "sessions_with_new_findings")},
        "skills_used_week": sum(1 for s in report["skills"] if s["uses_short"]),
        "skills_total": len(report["skills"]),
    }
    with history.open("a") as fh:
        fh.write(json.dumps(summary) + "\n")
    (STATE_DIR / "latest.json").write_text(json.dumps({
        "measured_at": report["generated_at"],
        "report_md": str(report_md),
        "report_json": str(report_json),
        "reviewed": False,
    }, indent=2))
    print(json.dumps({"report_md": str(report_md), "report_json": str(report_json), **summary}, indent=2))
    return 0


# ---------------------------------------------------------------------------
# Nudge and reviewed
# ---------------------------------------------------------------------------

def once_per_day(tag):
    """Return True the first time a tag is seen on a given day."""
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    stamp = STATE_DIR / f"nudged-{tag}"
    today = date.today().isoformat()
    try:
        if stamp.read_text().strip() == today:
            return False
    except OSError:
        pass
    stamp.write_text(today)
    return True


def cmd_nudge(_args):
    cfg = load_config()
    state = latest_state()
    measured = parse_ts(state.get("measured_at"))
    every = timedelta(days=int(cfg.get("measure_every_days") or 7))
    messages = []

    if not cfg.get("wiki_dir") and once_per_day("wiki"):
        messages.append(
            "skill-review: no wiki folder is set. Ask the user where wiki pages go, then run "
            f"`python3 {Path(__file__).resolve()} config --wiki-dir <path>`.")

    if measured is None or datetime.now(timezone.utc) - measured >= every:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        log = open(STATE_DIR / "measure.log", "a")
        subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "measure"],
                         stdout=log, stderr=log, stdin=subprocess.DEVNULL, start_new_session=True)
    elif not state.get("reviewed") and once_per_day("review"):
        messages.append(
            f"skill-review: the weekly skill report is ready and not reviewed: {state.get('report_md')}. "
            "Tell the user in one line and offer `/skill-review`.")

    if messages:
        print("\n".join(messages))
    return 0


def cmd_reviewed(_args):
    state = latest_state()
    if not state:
        print("No report to mark.", file=sys.stderr)
        return 1
    state["reviewed"] = True
    state["reviewed_at"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    (STATE_DIR / "latest.json").write_text(json.dumps(state, indent=2))
    print(f"Marked reviewed: {state.get('report_md')}")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    p_config = sub.add_parser("config", help="show or set the personal config")
    p_config.add_argument("--wiki-dir", dest="wiki_dir", help="folder for wiki pages ('' clears it)")
    p_config.add_argument("--proven-dir", dest="proven_skills_dir",
                          help="repo that holds promoted skills ('' clears it)")
    p_config.add_argument("--reports-subdir", help="subfolder of the wiki for weekly reports")
    p_config.add_argument("--wiki-ignore", help="comma-separated wiki subfolders that are logs, not wiki pages")
    p_config.set_defaults(func=cmd_config)

    p_measure = sub.add_parser("measure", help="scan sessions and write the weekly report")
    p_measure.add_argument("--days", type=int, default=7)
    p_measure.add_argument("--long-days", type=int, default=30)
    p_measure.add_argument("--no-wiki", action="store_true", help="write the report to the state folder only")
    p_measure.set_defaults(func=cmd_measure)

    sub.add_parser("nudge", help="SessionStart helper").set_defaults(func=cmd_nudge)
    sub.add_parser("reviewed", help="mark the latest report reviewed").set_defaults(func=cmd_reviewed)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
