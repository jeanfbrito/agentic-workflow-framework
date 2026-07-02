# Agentic Workflow Framework

Lightweight multi-agent orchestration conventions for Claude Code.

---

## What this installs

- **1 spec document** (`~/.claude/AGENTIC.md`) -- the full framework spec imported into every session via `CLAUDE.md`
- **10 subagent definitions** in `~/.claude/agents/`: planner, auditor, reviewer, builder-smart, builder-fast, builder-trivial, finder, researcher, tester, watcher
- **6 slash commands** in `~/.claude/commands/`: `/agentic`, `/init-agentic`, `/handoff`, `/blocker`, `/known-issue`, `/qq`
- **1 reinforcement hook** (`~/.claude/hooks/orchestrator.sh`) -- fires on UserPromptSubmit to prevent Orchestrator drift
- **2 `settings.json` hook entries** -- SessionStart (blocker/handoff scanner) + UserPromptSubmit (orchestrator reinforcement)
- **1 `CLAUDE.md` import line** -- `@AGENTIC.md` so the spec loads globally in every Claude Code session
- **2 skills** in `~/.claude/skills/`: agentic-workflow and personal-engineering-rules
- **6 permission globs** in `~/.claude/settings.json`: Write/Edit for `.localdev/workflow/**`, `.localdev/workflow/handoffs/**`, and `docs/KNOWN_ISSUES.md`

---

## Operational Tools

This framework pairs well with three external tools (all optional but recommended):

- **GitNexus** — code graph queries, impact analysis, call-chain tracing. Query before grepping.
- **context-mode** — sandbox large outputs (file reads, logs, test runs) so raw data never enters the context window.
- **RTK** — token-filtered shell command proxy for routine ops.

These are not bundled. Install separately. The framework's subagents and slash commands work without them — they just produce sharper results when present.

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

- **Inherit** (rides the session model) -- Planner and Auditor: deep deliberation and architectural decisions at whatever capability the session is already running.
- **Opus** -- builder-smart: complex implementation a fast builder would botch.
- **Sonnet** (smart model) -- Reviewer and builder-fast: quality-gate judgment and single scoped edits.
- **Haiku** (fast model) -- builder-trivial, Finder, Researcher, Tester, and Watcher: speed/cost-optimized mechanical tasks, run many in parallel.

---

## Runtime file layout

```
project-root/
├── .localdev/                      # add to .gitignore (not auto-ignored)
│   └── workflow/
│       ├── todo.md                 # tasks + done criteria
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

Edit `AGENTIC.md` or any agent/command file in this repo, then re-run `install.sh`. It is idempotent: framework files are overwritten, but `CLAUDE.md` content and existing `settings.json` hook entries beyond the two added by this installer are left intact.

---

## Example prompts

These natural-language prompts trigger orchestrator dispatch automatically:

- `"Refactor the auth middleware to use the new token model and add retry logic."` -- routes to builder-smart via planner brief.
- `"Where is the rate-limiter called in the codebase?"` -- routes to finder (read-only, parallel-safe).
- `"Leave a handoff — I'm picking this up tomorrow."` -- triggers `/handoff` flow from current session context.
- `"This bug only appears in production. Investigate and fix it."` -- triggers full-tier pipeline: finder traces call chain, builder-smart patches, tester validates.

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
