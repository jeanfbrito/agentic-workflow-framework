# Agentic Workflow Framework

Lightweight multi-agent orchestration conventions for Claude Code.

---

## What this installs

- **1 spec document** (`~/.claude/AGENTIC.md`) -- the full framework spec imported into every session via `CLAUDE.md`
- **8 subagent definitions** in `~/.claude/agents/`: planner, auditor, reviewer, builder-smart, builder-fast, finder, researcher, tester
- **5 slash commands** in `~/.claude/commands/`: `/agentic`, `/init-agentic`, `/handoff`, `/blocker`, `/known-issue`
- **1 reinforcement hook** (`~/.claude/hooks/orchestrator.sh`) -- fires on UserPromptSubmit to prevent Orchestrator drift
- **2 `settings.json` hook entries** -- SessionStart (blocker/handoff scanner) + UserPromptSubmit (orchestrator reinforcement)
- **1 `CLAUDE.md` import line** -- `@AGENTIC.md` so the spec loads globally in every Claude Code session

---

## Install

**Option 0: Claude Code plugin marketplace (no cloning)**

```sh
/plugin add jeanfbrito/agentic-workflow-framework
```

Claude Code downloads, installs, and activates the framework automatically. Hooks and slash commands are live immediately — no shell step required.

**Option 1: clone and run**

```sh
git clone https://github.com/jeanfbrito/agentic-workflow-framework.git ~/agentic-workflow-framework
cd ~/agentic-workflow-framework
./install.sh
```

Pass `--yes` / `-y` to skip the confirmation prompt. Pass `--link` to symlink instead of copy (dev mode — edits to the repo are reflected immediately).

**Option 2: agent-driven (Claude Code)**

Paste the raw URL of `install.md` into a Claude Code session. The agent reads the file and executes each step, prompting you for confirmation before writing any files.

---

## Uninstall

```sh
./uninstall.sh
```

Removes the 15 framework files and strips the hook entries and `@AGENTIC.md` import from `~/.claude/`. Backs up `CLAUDE.md` and `settings.json` before modifying them. Does not remove the `~/.claude/agents/`, `~/.claude/commands/`, or `~/.claude/hooks/` directories.

---

## Model mapping

- **Opus** (reasoning model) -- Planner and Auditor: deep deliberation, architectural decisions, never writes code directly.
- **Sonnet** (smart model) -- Reviewer and builder-smart: capable implementation and quality-gate judgment.
- **Haiku** (fast model) -- Finder, Researcher, builder-fast, and Tester: speed/cost-optimized mechanical tasks, run many in parallel.

---

## Runtime file layout

```
project-root/
├── .claude/                        # gitignored
│   └── mytasks/
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
| `/init-agentic` | Scaffold `.claude/mytasks/` + `docs/KNOWN_ISSUES.md` in the current project. |
| `/handoff <task-name>` | Write a cross-session handoff from current session context. |
| `/blocker <summary>` | Log an unresolved blocker in canonical format and halt. |
| `/known-issue <summary>` | Append a persistent platform constraint to `docs/KNOWN_ISSUES.md`. |

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
- **Verify the full installation**: `./verify.sh` from the repo root runs all 6 checks and prints `[x]` / `[ ]` per item. Exit code 0 means everything is healthy.
- **Hook fires but produces no output on short prompts**: That is expected behavior -- the orchestrator hook is a no-op for prompts under the word threshold.
- **Reinstall doesn't overwrite backups**: By design. The named backup (`.bak.agentic-workflow-framework`) is a one-shot pre-installation snapshot. Delete it manually if you want a fresh baseline.

---

## License

MIT -- see [LICENSE](LICENSE).
