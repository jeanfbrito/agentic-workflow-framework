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
- **5 hook scripts** in `~/.claude/hooks/`: `orchestrator.sh` (UserPromptSubmit reinforcement), `session-scan.sh` (SessionStart budgeted ledger digest), `skill-review-nudge.sh` (SessionStart weekly skill review), `pre-compact.sh` (PreCompact in-flight card snapshot), `stop-ledger-audit.sh` (Stop ledger hygiene audit)
- **1 utility script** (`~/.claude/hooks/ledger-append.sh`) -- lock-guarded `done.md`/`findings.md` appends and `decisions.tsv` rows. It is installed alongside the hooks but not wired to a hook event itself
- **5 `settings.json` hook entries** -- SessionStart (budgeted ledger digest) + SessionStart (weekly skill review) + PreCompact (in-flight card snapshot) + Stop (ledger hygiene audit) + UserPromptSubmit (orchestrator reinforcement)
- **1 `CLAUDE.md` import line** -- `@AGENTIC.md` so the spec loads globally in every Claude Code session
- **3 skills** in `~/.claude/skills/`: agentic-workflow, personal-engineering-rules, and skill-review. The `AGENTIC.md` Writing section uses the companion `asd-ste100` skill from [jeanfbrito/agent-skills](https://github.com/jeanfbrito/agent-skills) (`npx skills add jeanfbrito/agent-skills -s asd-ste100 -g`)
- **6 permission globs** in `~/.claude/settings.json`: Write/Edit for `.localdev/workflow/**`, `.localdev/workflow/handoffs/**`, and `docs/KNOWN_ISSUES.md`

---

## Wiki and weekly skill review

The framework asks each user for a **wiki folder**: an Obsidian vault or any
folder of Markdown notes. When Claude finds something new during work, it
writes a page there that teaches the mechanism. Set the folder in one of these
ways. Each one writes `~/.claude/agentic-config.json`, which a reinstall keeps:

- `./install.sh` asks for it, or pass `./install.sh --wiki-dir=PATH`.
- `python3 ~/.claude/skills/skill-review/scripts/skill_review.py config --wiki-dir PATH`
- Plugin installs have no installer prompt. The session-start hook tells
  Claude to ask, once per day, until you set the folder.

Optional settings: `--proven-dir PATH` (your repo of promoted skills) and
`--wiki-ignore "Daily,Logs"` (wiki subfolders that are logs, not pages).

Once every 7 days, the session-start hook runs a local measurement in the
background. It reads your Claude Code transcripts on this machine and writes a
report page into `<wiki>/Skill Reviews/`. The report shows:

- each skill, command, and plugin skill that actually ran (a real `Skill` call
  or a typed `/name`, not a name in text), grouped by stage.
- wiki pages written, and sessions that saved a lesson but wrote no page
  (missed wikis).

Run `/skill-review` to sort the skills into keep, merge, promote, or retire.
Nothing changes until you approve. Retired skills move to
`~/.claude/skills/.trash/`.

Skill stages: **project** (`<repo>/.claude/skills/`) → **trial**
(`~/.claude/skills/`, a plain folder) → **proven** (your skills repo, symlinked
in), after use in 2 or more weeks.

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

- **Inherit** (rides the session model) -- Planner: the general. It plans and does not fight, on the model the session already runs.
- **Fable** (strongest model) -- Auditor: the outside expert. The orchestrator calls it only after two failed approaches, so a stronger model diagnoses what the lower tier missed.
- **Opus** -- Reviewer and builder-smart: the officers. The Reviewer is the quality gate on risky diffs. builder-smart implements by exception: after a failed builder-fast attempt, for strategy-grade reasoning, or for prose that goes to a public repo.
- **Haiku** (fast model, effort high for builder-fast) -- builder-fast, builder-trivial, Finder, Researcher, Tester, and Watcher: the soldiers and scouts. They are cheap, and many run in parallel.
- **Sonnet** -- no role. In the 2026-10 A/B below, Haiku and Opus did better than Sonnet in this framework.

Why these tiers (prices as of 2026-10): subagent spend is mostly cached input,
and Opus and Sonnet charge the same for a cache read. On real subagent loops,
Opus costs about 1.35x to 1.7x Sonnet, not the 2x of the list price. So the
low-volume judgment roles (Reviewer, Auditor) move up a tier for little money.
Haiku costs 20x less than Sonnet. Above a 100K-token prompt, the Haiku price
goes up 5x, so the scouts keep their tool budgets and short prompts.

Why builder-fast runs on Haiku (A/B, 2026-10-10): 3 real builder briefs ran
again on 7 model and effort arms. A blind judge ranked the results. Opus
medium ranked first (mean rank 2.0) at $2.21 per 3 tasks. Haiku high ranked
second (3.0) at $0.52. Sonnet medium, the old builder-fast, ranked last (5.17)
at $0.97, and Sonnet high did not do better. Haiku needs 3 to 4 times more
turns, so one Haiku builder is slower. Builders that run in parallel hide that
cost. In one observed job, Opus with Haiku workers finished in about a fifth of
the time of Opus alone, at about the same cost. Haiku was weaker on prose for
a public repo, so that work goes to builder-smart.

When a new model generation arrives, measure before you change a role:

- `python3 scripts/role-spend.py --whatif` reads your local subagent
  transcripts. It shows the model that each role ran on, where the spend is,
  and what each role would cost on each current model. It counts the main
  sessions too, and `--top 10` lists the 10 most expensive single runs.
- `python3 scripts/role-ab.py check|run|judge|report spec.json` replays real
  briefs for one role on several models. Each arm runs in its own git
  worktree. A grader that you write runs the checks, and a blind judge ranks
  the arms. The docstring describes the spec format.

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
