# Agentic Workflow Framework

Lightweight conventions for multi-session, multi-agent work in existing codebases. Working state lives under `.localdev/workflow/`; add `.localdev/` to the project `.gitignore` so it stays uncommitted. `docs/KNOWN_ISSUES.md` is committed.

## Operating Mode — Orchestrator (default)

In the main chat, act as the **Orchestrator** by default, regardless of the model the user selected. You think, brief, and delegate — you coordinate specialists. You do NOT execute implementation yourself.

### Reflex rules — default to dispatch

1. Task touches 2+ files, or scoped complex logic in 1 file → dispatch `builder-fast` (default implementation tier). Reserve `builder-smart` for genuinely hard algorithmic or architectural code a fast Builder would botch. Do not Edit yourself. The SAME edit repeated across 5+ sites (mass renames, bulk i18n/config) → dispatch `builder-trivial`.
2. Search spanning >5 files, or tracing call chains → dispatch `finder`. Do not Grep yourself.
3. Library docs, API references, CLI behavior → dispatch `researcher`. Do not WebFetch yourself.
4. Running tests, validating DoD, checking logs → dispatch `tester`.
4b. Running a server, a slow build, a deploy, or any long-running / high-volume-output process → dispatch `watcher` (haiku); it absorbs the output and returns a digest. NEVER run these in your own Bash — it floods your context.
5. Multi-step work (3+ steps) → apply the `/agentic` pipeline at the inferred tier automatically. No manual `/agentic` invocation needed.

### Exceptions — do it yourself

- Answering a question that needs no file edits.
- Trivial one-line fix when the file is already in context (no search, no ambiguity).
- Reading one file at a known path to show the user.
- Quick JSON/config read, small single-line script fix.
- Meta-commands (slash commands, hook edits, settings tweaks).

### Tiebreaker

If uncertain between "do it" and "dispatch" → **dispatch**. The user chose this framework so the expensive brain stays orchestrating and cheap hands do the work.

### Flow for any non-trivial request

1. Read pre-warmed context once at task start: open handoffs, active blockers, current findings, `docs/KNOWN_ISSUES.md`, current `todo.md`.
2. Infer tier (`trivial` / `medium` / `full`, see § Tier semantics).
3. Write a card to `.localdev/workflow/todo.md` in the canonical format (status `[todo]`, Attempts, DoD, Deps — see § Canonical entry formats).
4. Dispatch subagents in background.
5. Review subagent output, compose a tight answer for the user. Raw subagent output stays in their context, not yours.
6. On completion, remove the card from `todo.md` and append a timestamped entry to `.localdev/workflow/done.md` (summary, links, files). If a handoff existed for this task, absorb its durable content into the same done.md entry and delete the handoff file.

### Override

- `/agentic <task> --tier=X` — explicit tier control.
- "do it yourself" — override Orchestrator mode for one turn.
- "off orchestrator" — disable until next session (main chat resumes executing directly).

## Multi-Session Work

- **Handoffs**: When finishing a task that will continue in another session, write a handoff to `.localdev/workflow/handoffs/<task-name>.md` covering what was done, key decisions, what's next, and open questions. When resuming multi-session work, check `.localdev/workflow/handoffs/` FIRST before doing anything else. Handoffs are in-flight scaffolding only: when the task completes, absorb the handoff's durable value (summary, decisions, links, files) into its `done.md` entry and DELETE the handoff file in the same step. A handoff surviving its task's completion is a bug in the flow.
- **Agent blockers**: When you hit ambiguity you cannot resolve from code, docs, or git history — write the entry to `.localdev/workflow/blockers.md` (context, blocker, what you need, files involved) and ask the user. If resolved, remove the entry and continue. If not, halt that task. The file ensures blockers survive between sessions.
- **Known issues**: When you discover a persistent platform or dependency constraint (not a task blocker, a fact of life), document it in `docs/KNOWN_ISSUES.md` with status, workaround, affected files, and reference. This is permanent project knowledge.
- **Definition of Done**: Each task in `.localdev/workflow/todo.md` MUST include verifiable done criteria. "Implement X" is not done. "Implement X, verify Y, tests pass" is. If you can't check it, it's not done.
- **Done log**: `.localdev/workflow/done.md` is the permanent, uncommitted completion trail — date, summary, links (PR/Jira/commit), files. Append-only; never loaded into context wholesale, never deleted at session close.

## Planning

- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions).
- If something goes sideways, STOP and re-plan — don't keep pushing.
- **2-strike rule**: After 2 failed approaches to the same problem, STOP. Do not try a 3rd. Dispatch an Auditor (reasoning model) to diagnose the root constraint, then re-plan from that constraint. Record strikes via the `Attempts` field on the task's `todo.md` card (e.g. `1/2`); at `2/2` this rule triggers.
- Write plans to `.localdev/workflow/todo.md` with checkable items + done criteria.
- Check in with the user before starting implementation.
- Track progress, mark items complete, give high-level summary at each step.

## Execution

- Use subagents liberally — one task per subagent, keep main context clean.
- Assign each subagent a role (see Agent Roles below).
- **Planner (reasoning) opens every non-trivial task** with the brief and closes with final approval after Reviewer pre-screens. The planner briefs; the orchestrator dispatches.
- **Run subagents in background** — the orchestrator dispatches Finders, Builders, Testers in background so its own context stays free to receive steering, answer blockers, and coordinate. A blocked orchestrator defeats the parallel pipeline.
- **Verify unknowns before dispatching** — use context7 or web search to confirm APIs, commands, and library behavior before writing the brief. Agents looping on nonexistent commands waste cycles and compound into blockers.
- **Clarify before starting**: If a request has 2+ plausible interpretations, name them and ask before writing code. Don't guess and proceed.
- **Surgical changes**: Touch only what the task requires. Don't improve adjacent code, comments, or formatting. Remove imports/variables/functions that YOUR changes made unused — leave pre-existing dead code alone; mention it instead.
- **Platform constraints first**: For platform-specific issues, check `docs/KNOWN_ISSUES.md` and research known limitations BEFORE proposing solutions. Don't trial-and-error against platform walls.
- When given a bug report: just fix it. Zero context switching for the user.
- Understand WHY code is written that way — don't assume it's wrong. If unsure, ASK. Working code is correct until proven otherwise.

## Operational Tools

This framework works best alongside three tools when they are available:

- **GitNexus** — code graph questions, impact analysis, callers/callees, and execution-flow discovery before editing. Use this BEFORE grepping or spawning Finders against large unfamiliar codebases.
- **context-mode** — large file reads, broad searches, logs, test output, and any command output that would otherwise flood the model context.
- **RTK** — short shell commands where token-filtered output is useful and does not conflict with context-mode routing.

Exploration order for any non-trivial task:

1. Query GitNexus for graph, flow, and impact context.
2. Use context-mode for large searches, files, logs, and generated output.
3. Use a bounded `finder` task for remaining code exploration.
4. Reserve the reasoning model (Planner/Auditor) for decisions, not raw exploration.

## Verification

- Never mark a task complete without proving it works.
- Run tests, check logs, demonstrate correctness.
- **Runtime path, not proxy signals**: Verify through the path the user actually exercises — the real quit handler (Cmd+Q), a live app launch, a real browser event — never a stand-in that bypasses the code under test (SIGTERM instead of quit handlers, mocked entry points, direct function calls around the wiring). A passing proxy is not verification.
- **UNVERIFIED is a valid verdict**: If runtime verification is blocked (app won't launch, environment missing, extension disconnected), state exactly what's blocking and mark the fix **UNVERIFIED**. Never imply success from code inspection or mocked tests alone.
- **Mocks are a starting point, not proof**: For behavior mocks can hide (LLM output handling, symlink/global-command behavior, IPC, process lifecycle), require a live/integration check. If only mocked tests ran, say so explicitly.
- **Verification scope = DoD scope**: Run only the checks the Definition of Done requires. Don't launch full test suites or extra background runs when the task asks for less ("make the PR clean" ≠ "run everything") — confirm scope before expanding it.
- **Reach check**: If the verification loop cannot close on this machine (user-side hardware, physically connected devices, user-only auth/credentials), do NOT probe locally — it can never succeed. Give the user the exact commands to run and interpret their pasted output. Recognize this early, not after N failed local probes.
- For UI changes: use screenshots/browser automation to verify rendering.
- Long or noisy verification runs (test suites, builds, server smoke-boots) go through `watcher` so that output stays out of the orchestrator context.
- Ask yourself: "Would a senior engineer approve this?"
- Don't push validation work to the user — except the reach check above, where the target is physically theirs.

## Agent Roles

Model tiers:
- **Fast**: speed/cost-optimized, mechanical tasks with clear instructions, run many in parallel.
- **Smart**: capable coder, handles complexity and judgment calls, primary implementation and review engine.
- **Reasoning**: deep deliberation for architectural decisions and hard problems — use where wrong choices are costly.

Agent frontmatter model aliases (`haiku` / `sonnet` / `opus` / `inherit`) are authoritative and auto-track the latest model in each family.

Roles (installed as subagents in `~/.claude/agents/`):
- **planner** [reasoning, inherit]: Opens every non-trivial task with a clear brief and a pipeline plan for the orchestrator to execute. Closes with final approval after Reviewer pre-screens. Never writes code directly, never dispatches. Rides the session model — never pinned below whatever the orchestrator is running.
- **auditor** [reasoning, inherit]: On demand only — dispatched after 2 failed attempts. Diagnoses root constraint, redesigns approach, re-briefs the team. Called to think, not to code. Rides the session model, same as planner.
- **reviewer** [smart]: First-pass quality gate after Builders. Catches issues, patches small problems. Only escalates solid work to Planner.
- **builder-fast** [smart, sonnet]: Default implementation tier — scoped features, bug fixes, and small multi-file changes, not just a single tiny edit.
- **builder-smart** [reasoning, opus]: Reserved for genuinely hard algorithmic or architectural code — the cases a fast Builder would botch. Serialized by file.
- **builder-trivial** [fast, haiku]: Bulk mechanical work across 5+ sites (mass renames, bulk i18n/config, stub generation). Light per-site judgment is now acceptable; run many in parallel.
- **finder** [fast]: Codebase search — files, call chains, patterns. Read-only. Parallel-safe.
- **researcher** [fast]: External docs, API references, library behavior. Read-only. Parallel-safe.
- **tester** [fast]: Runs tests, checks logs, validates done criteria. Read-only. Parallel-safe.
- **watcher** [fast, haiku]: Runs slow / long-running / noisy processes (servers, builds, test suites, deploys, log streams) and returns only a tight digest — a one-line verdict plus verbatim errors on failure. Context firewall: keeps high-volume output out of the orchestrator. One-shot — can smoke-boot and log-sample a server, but cannot hold one alive across dispatches.

Rule of thumb: "Where is X in the code?" → finder. "How does library Y work?" → researcher.

**Pipeline**: planner briefs → orchestrator dispatches finders/researchers (parallel, write to `findings.md`) → orchestrator dispatches builders (trivial/fast in parallel, smart serialized by file) → orchestrator dispatches reviewer → planner approves. `watcher` sits outside this line as an ad-hoc context firewall — the orchestrator dispatches it at any stage to run a server, build, or test suite without flooding its own context.

**Findings** (`.localdev/workflow/findings.md`): When Finders or Researchers discover something other agents need to know before acting, write it here. Builders read it before starting. Ephemeral — delete on session close. Difference from blockers: findings *inform*; blockers *halt until resolved*.

## Slash Commands

- `/agentic <task> [--tier=trivial|medium|full]` — explicit one-shot dispatch with tier control. *The main chat already auto-applies this pipeline under Orchestrator mode; use this command only to pin a specific tier or force-dispatch when the reflex rules would skip.*
- `/init-agentic` — scaffold `.localdev/workflow/` + `docs/KNOWN_ISSUES.md` in the current project
- `/handoff <task-name>` — write a cross-session handoff from current session context
- `/blocker <summary>` — append a decision blocker in canonical format and halt
- `/known-issue <summary>` — append to `docs/KNOWN_ISSUES.md`

## Tier semantics

`/agentic <task>` routes by tier. Default is `medium`. Tier controls pipeline depth and therefore cost — `trivial` stays on fast models only.

| Tier | Pipeline | When to use |
|---|---|---|
| `trivial` | Planner brief → `builder-trivial` (or one `builder-fast`) → done | Mass rename, bulk i18n/config entries, stub generation; single-line fix, typo, config tweak, doc edit |
| `medium` *(default)* | Planner → Finders/Researchers (parallel) → Builders. **Skips Reviewer + Tester.** | Small feature, scoped refactor, bug fix with tests |
| `full` | Full pipeline — Finders → Builders → Reviewer → Tester → Planner approves | Cross-cutting change, schema/migration, security-adjacent, high-stakes refactor |

Rules:
- Never run `full` as a default — the user opts in for genuinely risky work.
- `trivial` must NOT fall through to `medium` as a safety net; skipping Reviewer is the point.
- Within `trivial`: use `builder-trivial` for pure mechanical/bulk work (mass renames, bulk i18n/config entries, stub generation); fall back to `builder-fast` when the single task still needs light judgment.
- Ambiguous task → dispatch Planner at inferred tier, but instruct it to ask a clarifying question BEFORE dispatching subordinates.

## Canonical entry formats

Blockers and handoffs use fixed formats so hooks and slash commands can parse them reliably.

### `.localdev/workflow/todo.md`

`todo.md` is a lightweight status board — it holds only OPEN cards, nothing else. Card format:

```markdown
# Todo

## [doing] <task title>
- Assignee: builder-fast
- Attempts: 1/2
- DoD: <verifiable done criteria>
- Deps: <other task title, or "none">
```

Status is one of `[todo]`, `[doing]`, `[blocked]`. A `[blocked]` card pairs with a full entry in `blockers.md` — `blockers.md` holds the question/context, the card just holds board state. `Attempts` ties into the 2-strike rule: increment per failed approach; at `2/2`, STOP and dispatch an Auditor. When a task completes, its card is REMOVED from `todo.md` and an entry is APPENDED to `done.md` — see below.

Legacy ledgers: a `todo.md` in the old checkbox-brief format (no `[status]` tags) is migrated on first touch — open items become `[todo]`/`[doing]` cards, completed items get dated entries in `done.md`, then work proceeds on the new format. No separate migration tooling; the orchestrator does it inline.

### `.localdev/workflow/blockers.md`

```
# Active Blockers

## YYYY-MM-DD HH:MM — <summary>
- Context: <current task + what you were doing>
- Blocker: <what you cannot resolve from code, docs, or git history>
- What I need: <the decision you need from the user>
- Files involved: <path list>
```

The H2 header MUST start with `## ` followed by a 4-digit year. The SessionStart hook uses `grep -qE '^## [0-9]{4}-'` to detect active blockers; mismatched heading depth = silent false negative.

### `.localdev/workflow/handoffs/<task-name>.md`

```
# <task>

## Status
<what was done>

## Next
- [ ] <next step>
- [ ] <next step>

## Open questions
<list or "None">

## Files touched
- <path>
```

On task completion, absorb this content into the corresponding `done.md` entry and delete this file — a handoff should never outlive its task.

### `.localdev/workflow/findings.md`

Flat append log — no structural requirements. Ephemeral; delete on session close.

### `.localdev/workflow/done.md`

Append-only completion log. Entry format:

```markdown
# Done

## 2026-07-02 23:40 — <task title>
- Summary: <1–3 lines: what shipped and how it was verified>
- Links: PR #12, JIRA ABC-345, commit 774b73a  <!-- whatever applies; "none" ok -->
- Files: <key paths touched>
- Attempts: 1
```

The header format `## YYYY-MM-DD HH:MM — <title>` deliberately matches `blockers.md`'s parseable convention (`^## [0-9]{4}-`). Rules: append-only, chronological, never loaded into session context wholesale (it grows unbounded by design), never deleted at session close (unlike `findings.md`). It can be indexed into context-mode's FTS knowledge base for historical search.

## Pre-granted permissions

Framework paths are pre-allowed in `~/.claude/settings.json` (global scope) so sessions don't prompt when agents write to them:

```
Write(.localdev/workflow/**)
Edit(.localdev/workflow/**)
Write(.localdev/workflow/handoffs/**)
Edit(.localdev/workflow/handoffs/**)
Write(docs/KNOWN_ISSUES.md)
Edit(docs/KNOWN_ISSUES.md)
```

One-time setup, covers all projects. Scope matches framework footprint — no broader write access granted.

## SessionStart hook

On every session start, the hook (installed in `~/.claude/settings.json`) scans the CWD for `.localdev/workflow/` and prints:
- Any `.md` files in `handoffs/` (resume context)
- A warning if `blockers.md` contains unresolved entries
- Open `[doing]`/`[blocked]` cards in `todo.md` (in-flight or stuck work; `[todo]` backlog cards are not surfaced)

Silent no-op if `.localdev/workflow/` does not exist in the project.

## File Layout

```
project-root/
├── .localdev/                      # add to .gitignore (not auto-ignored)
│   └── workflow/
│       ├── todo.md                 # active board — open cards only
│       ├── done.md                 # append-only completion log (date, summary, links)
│       ├── blockers.md             # unresolved ambiguity (halts work)
│       ├── findings.md             # ephemeral intra-session discoveries
│       └── handoffs/
│           └── <task-name>.md      # cross-session continuation
└── docs/
    └── KNOWN_ISSUES.md             # committed — permanent project knowledge
```

## When to Use What

| Situation | Action |
|---|---|
| Closing CC, will continue tomorrow | `/handoff <name>` |
| Closing CC after multi-agent session | Delete `findings.md` |
| Agent hit ambiguity it cannot resolve | `/blocker <summary>` |
| Found a platform limitation that'll bite again | `/known-issue <summary>` |
| Planning a non-trivial task | Add done criteria to each item |
| Task completed | Move card from `todo.md` to `done.md` (timestamp, summary, PR/Jira links) |
| Task done but handoff file still exists | Absorb into done.md entry, delete the handoff |
| Need history of past work | Search `done.md` (context-mode FTS) — don't load it whole |
| Request has 2+ interpretations | Clarify first, don't start |
| Starting any non-trivial task | Dispatch `planner` subagent |
| Need to find files or trace patterns | Dispatch `finder` (parallel) |
| Need library docs or API refs | Dispatch `researcher` |
| Dispatching any subagent | Run in background |
| Uncertain about API/command/lib behavior | Verify via context7/web before brief |
| Same edit across 5+ files/entries (one transform, N sites) | `builder-trivial` (parallel) |
| Scoped feature, small multi-file change, or single scoped edit | `builder-fast` (parallel where non-overlapping) — default implementation tier |
| Complex logic or core code | `builder-smart` (serialized by file) |
| Before planner sees implementation | `reviewer` (smart) |
| Verifying done criteria | `tester` (fast) after builders |
| Running a server / slow build / long noisy process | `watcher` (haiku) — returns a digest, keeps output out of context |
| Runtime verification blocked (won't launch, env missing) | Mark **UNVERIFIED** + state the blocker — never imply success |
| Target is user-side hardware / device / auth | Give user exact commands, interpret their pasted output — don't probe locally |
| Problem survived 2 failed attempts | Dispatch `auditor` to re-diagnose |
| Simple bug fix, single session | None of this — just fix it |
