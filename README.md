# Agentic Workflow Framework

Lightweight task continuity and optional agent coordination for Claude Code.

---

## Working conventions

Handle clear, bounded work directly. Add planning, continuity, and authorized
delegation when they help the task. Continue through the requested outcome and
focused checks without a routine planning approval or repeated test round.

`AGENTIC.md` contains the shared guidance. Detailed
[ledger formats](skills/agentic-workflow/references/ledgers.md) and
[delegation mechanics](skills/agentic-workflow/references/delegation.md) are
loaded only when needed. Skills have concise descriptions for their actual use
cases; file counts and ordinary engineering keywords do not force a pipeline.

---

## What this installs

- **1 entry document** (`~/.claude/AGENTIC.md`) -- shared guidance imported via `CLAUDE.md`, with conditional references packaged inside the workflow skill.
- **10 subagent definitions** in `~/.claude/agents/`: planner, auditor, reviewer, builder-smart, builder-fast, builder-trivial, finder, researcher, tester, watcher
- **6 slash commands** in `~/.claude/commands/`: `/agentic`, `/init-agentic`, `/handoff`, `/blocker`, `/known-issue`, `/qq`
- **4 hook scripts** in `~/.claude/hooks/`: `orchestrator.sh` (UserPromptSubmit reinforcement), `session-scan.sh` (SessionStart budgeted ledger digest), `pre-compact.sh` (PreCompact in-flight card snapshot), `stop-ledger-audit.sh` (Stop ledger hygiene audit)
- **1 utility script** (`~/.claude/hooks/ledger-append.sh`) -- lock-guarded `done.md`/`findings.md` appends; installed alongside the hooks but not wired to a hook event itself
- **4 `settings.json` hook entries** -- SessionStart (budgeted ledger digest) + PreCompact (in-flight card snapshot) + Stop (ledger hygiene audit) + UserPromptSubmit (orchestrator reinforcement)
- **1 `CLAUDE.md` import line** -- `@AGENTIC.md` so the spec loads globally in every Claude Code session
- **2 skills** in `~/.claude/skills/`: agentic-workflow and personal-engineering-rules
- **6 permission globs** in `~/.claude/settings.json`: Write/Edit for `.localdev/workflow/**`, `.localdev/workflow/handoffs/**`, and `docs/KNOWN_ISSUES.md`

---

## Operational Tools

This framework treats three external tools as first-class infrastructure:

- **[GitNexus](https://github.com/abhigyanpatwari/GitNexus)** — indexed structural and impact questions, with bounded source inspection for gaps.
- **[context-mode](https://github.com/mksglu/context-mode)** — processing large searches, logs, and data; native reads and edits remain appropriate for patching.
- **[context7](https://github.com/upstash/context7)** — primary documentation for uncertain or version-sensitive API and CLI behavior.
- **[RTK](https://github.com/rtk-ai/rtk)** — token-filtered shell command proxy for routine ops.

These are not bundled. Report tool failures and any evidence gaps, then use an
available, permitted alternative. Installing tools or expanding permissions is
a separate task.

---

## Install

**Option 0: Claude Code plugin marketplace (no cloning)**

```sh
/plugin add jeanfbrito/agentic-workflow-framework
```

Claude Code downloads, installs, and activates the framework automatically. Hooks, slash commands, agents, and skills are live immediately — no shell step required.

The plugin sandbox cannot edit `~/.claude/CLAUDE.md` or `settings.json`, so the plugin closes those two gaps with its own hooks:

- **Always-on conventions**: a SessionStart hook injects `AGENTIC.md` into every session's context (it no-ops when the shell installer's `@AGENTIC.md` import is present, so nothing loads twice).
- **Permissions**: a PreToolUse hook auto-allows Write/Edit on `.localdev/workflow/**` and `docs/KNOWN_ISSUES.md`, mirroring the permission globs `install.sh` grants. All other paths follow the normal permission flow.

Both paths land on the same conventions but wire them up differently: the plugin path relies on its own hooks (context injection, orchestrator reinforcement, permission auto-allow) since it cannot touch `~/.claude/CLAUDE.md` or `settings.json`; the shell path instead writes the `@AGENTIC.md` import into `CLAUDE.md` and the permission globs directly into `settings.json`. Same end behavior via different mechanisms.

**Option 1: clone and run**

```sh
git clone https://github.com/jeanfbrito/agentic-workflow-framework.git ~/agentic-workflow-framework
cd ~/agentic-workflow-framework
./install.sh
```

Pass `--yes` / `-y` to skip the confirmation prompt. Pass `--link` to symlink instead of copy (dev mode — edits to the repo are reflected immediately).

> The agent-driven self-installer has been retired (its embedded file copies drifted from the source of truth). Use the plugin marketplace path or the shell installer above.

---

## Uninstall

```sh
./uninstall.sh
```

Removes the framework files, installed skills, and permission globs. By default this is a surgical strip: it removes only the framework's hook entries, permission globs, and `@AGENTIC.md` import, preserving anything else you've added to `CLAUDE.md` or `settings.json` since installing. Pass `--restore-backup` to instead wholesale-restore `CLAUDE.md` and `settings.json` from the pre-install backup snapshot, discarding all edits made since install. Does not remove the `~/.claude/agents/`, `~/.claude/commands/`, `~/.claude/hooks/`, or `~/.claude/skills/` directories themselves.

---

## Model mapping

These aliases configure delegated Claude Code roles. They do not change the
main conversation's selected model or require delegation.

- **Inherit** (rides the session model) -- Planner and Auditor: the general — plans and diagnoses, doesn't fight; deep deliberation at whatever capability the session is already running.
- **Opus** -- builder-smart: the general picking up a weapon — exception only, when a sonnet attempt failed or the code demands strategy-grade reasoning.
- **Sonnet** (smart model) -- Reviewer and builder-fast: the soldiers — primary implementation and quality-gate judgment.
- **Haiku** (fast model) -- builder-trivial, Finder, Researcher, Tester, and Watcher: the scouts — cheap, fast, run many in parallel.

---

## Runtime file layout

```
project-root/
├── .localdev/                      # add to .gitignore (not auto-ignored)
│   └── workflow/
│       ├── todo.md                 # open tasks + done criteria
│       ├── done.md                 # append-only completion evidence
│       ├── blockers.md             # unresolved ambiguity (halts work)
│       ├── findings.md             # ephemeral intra-session discoveries
│       └── handoffs/
│           └── <task-name>.md      # cross-session continuation
└── docs/
    └── KNOWN_ISSUES.md             # committed -- permanent project knowledge
```

---

## Slash commands

| Command | Summary |
|---|---|
| `/agentic <task> [--tier=trivial\|medium\|full]` | Front door for any non-trivial task. Tier is inferred automatically. |
| `/init-agentic` | Scaffold `.localdev/workflow/` + `docs/KNOWN_ISSUES.md` in the current project. |
| `/handoff <task-name>` | Write a cross-session handoff from current session context. |
| `/blocker <summary>` | Log an unresolved blocker in canonical format and halt. |
| `/known-issue <summary>` | Append a persistent platform constraint to `docs/KNOWN_ISSUES.md`. |
| `/qq <question>` | Quick side question answered by a fast/cheap model (haiku) in one turn with full conversation context — repeat `/qq` to continue the side thread; session model untouched. |

---

## Customizing

Edit `AGENTIC.md` or any agent/command file in this repo, then re-run `install.sh`. It is idempotent: framework files are overwritten, but `CLAUDE.md` content and existing `settings.json` hook entries beyond the four added by this installer are left intact.

---

## Example prompts

Define the outcome and any useful stopping boundary:

- `"Refactor the auth middleware to use the new token model. Preserve retry behavior and run the affected tests."`
- `"Find the rate-limiter's callers and explain the request path."`
- `"Leave a handoff — I'm picking this up tomorrow."`
- `"Investigate this production-only bug, implement the fix, and validate the behavior locally. Report any remaining production evidence gap."`

The task determines the needed workflow; these prompts do not automatically
dispatch agents or authorize production changes.

---

## Troubleshooting

- **Slash commands not appearing**: Ensure `~/.claude/commands/` exists and contains the `.md` files. Re-run `./install.sh --yes` if in doubt.
- **Orchestrator hook not firing**: Check that `~/.claude/hooks/orchestrator.sh` is executable (`chmod +x`) and that `settings.json` contains the `UserPromptSubmit` entry. Run `./verify.sh` to diagnose.
- **Verify the full installation**: `./verify.sh` from the repo root runs all checks (files, hooks, skills, permission globs, repo structure) and prints `[x]` / `[ ]` per item. Exit code 0 means everything is healthy.
- **Hook fires but produces no output on short prompts**: That is expected behavior -- the orchestrator hook is a no-op for prompts under the word threshold.
- **Reinstall doesn't overwrite backups**: By design. The named backup (`.bak.agentic-workflow-framework`) is a one-shot pre-installation snapshot. Delete it manually if you want a fresh baseline.

---

## License

MIT -- see [LICENSE](LICENSE).
