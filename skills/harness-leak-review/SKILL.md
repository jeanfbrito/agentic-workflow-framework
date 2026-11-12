---
name: harness-leak-review
description: Finds and removes personal harness tools in the guidance of a shared repository. Personal tools are your MCP servers, plugins, agents and skills, ~/.claude paths and agentic-workflow ledgers. The goal is guidance that works for a teammate who has none of them. Use it to review or clean the agent guidance of a repository. Use it before a PR that changes AGENTS.md, CLAUDE.md, .claude/, skills or docs. Triggers - "does this repo depend on my setup", "remove my tools from the project", "harness leak", or a finding from the harness-leak hook.
---

# Harness leak review

A shared repository's guidance must work for every contributor and every
agent harness. Your personal tools are code-graph servers, VM labs, sandboxes, your
framework's agent roles and your skills. They belong in your own setup: the
agentic-workflow framework, `~/.claude`, or the project's auto-memory. When
a repo names them, a teammate gets "MUST" rules for tools they do not have,
and agents call roles that do not exist.

`scripts/harness_leaks.py` finds these mentions. It reads your setup to learn
what is personal, so the list stays current. It looks for:

- the user-scope MCP servers in `~/.claude.json`
- the plugins from a marketplace other than the official one
- the agents in `~/.claude/agents`
- the skills in `~/.claude/skills` that the repository does not ship
- any `mcp__*` tool name, `~/.claude` and home-directory paths,
  `.localdev/workflow` and `AGENTIC.md`

## Review a repository

1. List what counts as personal: `python3 ~/.claude/skills/harness-leak-review/scripts/harness_leaks.py inventory`.
2. Scan the agent-facing files (`*.md`, `.claude/`, `.github/`, `skills/`):
   `python3 ~/.claude/skills/harness-leak-review/scripts/harness_leaks.py scan --repo <path>`.
   Add `--rev origin/<default>` to scan the published branch, and
   `--all-files` to include source code.
3. For a branch, scan only what it adds:
   `... diff --repo <path> --base "$(git merge-base origin/<default> HEAD)"`.
4. Fix each finding with the table below. Then scan again until it reports
   none, or only the mentions that you allow on purpose.

## Fix each kind

| Finding | Fix |
| --- | --- |
| A rule that requires your tool ("MUST run impact", "use X, not grep") | Move the rule to your framework (for example a reference under `skills/agentic-workflow/references/`). In the repo, keep the action without the tool: "find every caller", "check that only the expected files changed". |
| Your framework's agent roles (`watcher`, `builder-*`, `researcher`) | Describe the action: "run it in the background or in a subagent", "run the two jobs in parallel when you can". |
| `mcp__*` tool names in a skill or agent | Describe the action. Keep the name only for a public plugin that the file also covers with a fallback, and allow it. |
| `~/.claude/...` paths, your home directory | Name what the script reads (environment variables, a public tool's config file). |
| `.localdev/workflow`, `AGENTIC.md`, your auto-memory | Use a neutral gitignored path, and state the fact itself instead of citing your memory. |
| Generated files from a personal tool (index config, generated skills, an `AGENTS.md` block) | Untrack them (`git rm --cached`), and list them in `.git/info/exclude`. |
| A hook or permission for your tool in `.claude/settings.json` | Move it to `~/.claude/settings.json` (or the framework installer). |

Keep a personal tool in the repository only when three conditions are true.
It is an optional, concrete path with a fallback. It is public. The user
decides to keep it. Record that decision in the allow file.

## Allow an intended mention

Each repository has a local allow file that is never committed:
`$(git rev-parse --git-common-dir)/info/harness-leaks-allow`. One entry per
line: `<token-glob>` or `<token-glob> <path-glob>`, with `#` comments. Write
the reason as a comment above the entry.

## The hook

The framework installs `harness_leaks.py --hook` as a PreToolUse hook on
`Edit|Write|MultiEdit|Bash`. It gives advice and never blocks:

- On an edit to an agent-facing file of a shared repository, it reports each
  personal tool that the new text adds. It ignores the tools already there.
- On `git commit`, it scans the staged added lines.
- It stays silent for subagents, for repositories with no GitHub remote, and
  for owners listed in `~/.claude/agentic-config.json` under
  `harness_leaks.skip_owners` (your personal repositories).

## Checks

Run the tests after a change to the script:
`python3 -m unittest skills/harness-leak-review/tests/test_harness_leaks.py`
from the framework repository.
