#!/usr/bin/env python3
"""Flag shouted rules in the prompts this framework ships.

Current models follow a calm rule. A rule in capitals ("NEVER", "MUST",
"MANDATORY") makes them overreact: more tool calls and worse results. This
check scans the agent, command and skill prompts and AGENTIC.md for those
words. Text in backticks or double quotes is skipped, so a quoted example
("MUST run impact") stays legal.

Usage: check-emphasis.py [repo_root] [file ...]
Exit 0 when clean, 1 with one line per finding.
"""
import pathlib
import re
import sys

WORDS = re.compile(r"\b(NEVER|MUST|MANDATORY|IMPORTANT|ALWAYS|HALT)\b")
QUOTED = re.compile(r"`[^`]*`|\"[^\"\n]*\"|“[^”\n]*”")
FENCE = re.compile(r"^\s*```")


def shipped(root: pathlib.Path):
    yield root / "AGENTIC.md"
    for pattern in ("agents/*.md", "commands/*.md", "skills/*/SKILL.md", "skills/*/references/*.md"):
        yield from sorted(root.glob(pattern))


def findings(path: pathlib.Path, text: str):
    in_fence = False
    for n, line in enumerate(text.splitlines(), 1):
        if FENCE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        for m in WORDS.finditer(QUOTED.sub("", line)):
            yield f"{path}:{n}: '{m.group(1)}' in capitals. Write the rule calmly and give its reason."


def main(argv):
    root = pathlib.Path(argv[1]) if len(argv) > 1 else pathlib.Path(__file__).resolve().parent.parent
    files = [pathlib.Path(f) for f in argv[2:]] or [p for p in shipped(root) if p.is_file()]
    out = [f for p in files for f in findings(p, p.read_text(encoding="utf-8"))]
    print("\n".join(out)) if out else None
    return 1 if out else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
