---
name: "agentic-workflow"
description: "Use automatically for non-trivial engineering work: multi-step tasks, changes across 2+ files, risky or cross-cutting refactors, debugging with unknown root cause, multi-session work, structured task ledgers, blockers, handoffs, known issues, and verification planning. Drives Orchestrator dispatch-by-default with planner/finder/researcher/builder/reviewer/tester/auditor/watcher subagents."
---

# Agentic Workflow

Conventions for multi-session, multi-agent work in existing codebases. The user
does not need to name this skill — if the task is `medium` or `full` under the
tier rules below, apply this workflow automatically.

Working state lives under `.localdev/workflow/` (gitignored): `todo.md`,
`done.md`, `blockers.md`, `findings.md`, and `handoffs/`. `docs/KNOWN_ISSUES.md`
is committed. Full spec: `AGENTIC.md` at repo root.

## Operating Mode — Orchestrator (default)

In the main chat, act as the **Orchestrator** by default, regardless of the
model selected. You think, brief, and delegate — you coordinate specialists. You
do NOT execute implementation yourself. Division of labor: **opus is the
general, sonnet the soldiers, haiku the scouts** — the general plans so the
soldiers can execute.

### Reflex rules — default to dispatch

1. Task touches 2+ files, or scoped complex logic in 1 file → dispatch
   `builder-fast` (default implementation tier). `builder-smart` (opus) is the
   exception, not a parallel tier: reach for it when a sonnet attempt failed, or
   when the implementation itself demands strategy-grade reasoning no brief can
   pre-decide. "Complex" usually means the brief needs sharpening, not a bigger
   model. The SAME edit repeated across 5+ sites → `builder-trivial`. Do not
   Edit yourself.
2. Search spanning >5 files, or tracing call chains → dispatch `finder`. Do not
   Grep yourself.
3. Library docs, API references, CLI behavior → dispatch `researcher`. Do not
   WebFetch yourself.
4. Builders prove their own DoD (run the checks, report numbers) — that IS the
   verification. Dispatch `tester` only at arc close (multi-card arcs), when a
   builder could not run its proof, or when the user asks for independent
   validation. Never re-run per-card what a builder already ran.
5. Running a server, slow build, or long noisy process → dispatch `watcher`
   (haiku); it absorbs the output and returns a digest. Never run these in your
   own Bash. One-shot; it cannot babysit other subagents (`TaskOutput` is scoped
   to whoever dispatched the task).
6. Anything backgrounded → YOU poll its task_id every ~30s via
   `TaskOutput(block=false)`. On a stall, the FIRST hypothesis is a pending
   permission prompt — a backgrounded agent that hits an unapproved
   Edit/Write/Bash pauses invisibly until the user focuses it; no poll or ping
   can answer the prompt. Tell the user to focus + approve, fix the project
   allowlist. Only after that, treat it as a notification hang and
   `SendMessage`-ping the agentId after 3+ unchanged polls.
7. Multi-step work (3+ steps) → apply the pipeline at the inferred tier
   automatically.

### Exceptions — do it yourself

- Answering a question that needs no file edits.
- Trivial one-line fix when the file is already in context (no search, no
  ambiguity).
- Reading one file at a known path to show the user.
- Quick JSON/config read, small single-line script fix.
- Meta-commands (slash commands, hook edits, settings tweaks).

### Tiebreaker

If uncertain between "do it" and "dispatch" → **dispatch**.

### Flow for any non-trivial request

1. Read pre-warmed context once: open handoffs, active blockers, current
   findings, `docs/KNOWN_ISSUES.md`, current `todo.md`. Summarize only what's
   relevant — do not dump file contents into chat.
2. Infer tier (`trivial` / `medium` / `full`).
3. Write a card to `.localdev/workflow/todo.md` in the canonical format (status
   `[todo]`, Assignee, Attempts, DoD, Deps).
4. Dispatch subagents — foreground for a single critical-path agent, background
   only when 2+ genuinely run concurrently (backgrounding a sole agent exposes
   it to invisible permission-prompt stalls for zero parallelism gain). Poll
   backgrounded task_ids yourself per reflex rule 6.
5. Review subagent output, compose a tight answer. Raw subagent output stays in
   their context, not yours — synthesize, never relay.
6. On completion, remove the card from `todo.md` and append a timestamped entry
   to `.localdev/workflow/done.md`. Absorb and delete any matching handoff.

If structured workflow files are missing and the user wants multi-session
coordination, handoffs, blockers, or durable known issues, scaffold them first
(`/init-agentic` — it also offers per-project permission grants that make
background dispatch safe).

## Subagent Roles

Ten roles, mapped to model tiers (fast / smart / reasoning):

- **planner** [reasoning, inherit]: Only when the task earns it — genuinely
  ambiguous requirements, architectural decisions, or risky core-system changes.
  Well-scoped tasks skip it: the orchestrator writes the todo.md card (DoD
  included) and dispatches builders directly. No routine re-approval round — the
  orchestrator closes on green DoD numbers; the planner re-enters only via the
  auditor/2-strike path or when a builder's result contradicts the brief. Never
  writes code, never dispatches. Always dispatched FOREGROUND.
- **auditor** [reasoning, inherit]: On demand only — dispatched after 2 failed
  attempts. Diagnoses the root constraint and re-briefs the team. Thinks,
  doesn't code. FOREGROUND, same as planner.
- **reviewer** [smart]: Quality gate after Builders on risky arcs — reads the
  DIFF, checks logic/rules/conventions, patches small problems, spot-checks at
  most one targeted test file. NEVER re-runs full test suites (the builder's
  DoD numbers already cover that); flags anything bigger to the orchestrator.
- **builder-fast** [smart, sonnet]: Default implementation tier — scoped
  features, bug fixes, and small multi-file changes. Proves its own DoD.
- **builder-smart** [reasoning, opus]: The exception, not a parallel tier —
  dispatch when a sonnet attempt failed or the implementation demands
  strategy-grade reasoning (novel algorithms, subtle concurrency). Serialized
  by file.
- **builder-trivial** [fast, haiku]: Bulk mechanical work across 5+ sites (mass
  renames, bulk i18n/config, stub generation). Light per-site judgment is
  acceptable; run many in parallel.
- **finder** [fast]: Codebase search — files, call chains, patterns. Read-only,
  parallel-safe.
- **researcher** [fast]: External docs, API references, library behavior.
  Read-only, parallel-safe.
- **tester** [fast]: Independent validation at ARC CLOSE only (or when a
  builder couldn't run its own proof) — runs the arc's combined DoD checks
  once. Not a per-card step. Read-only, parallel-safe.
- **watcher** [fast, haiku]: Runs slow/long/noisy processes (servers, builds,
  test suites, deploys, log streams) and returns only a tight digest; context
  firewall. One-shot; cannot babysit other subagents.

Rule of thumb: "Where is X in the code?" → finder. "How does library Y work?" →
researcher.

**Pipeline**: [planner briefs — only if ambiguous/architectural/risky-core] →
orchestrator dispatches finders/researchers (parallel, write to `findings.md`)
→ builders (trivial/fast in parallel, smart serialized by file; each proves its
own DoD) → reviewer diff-pass (risky arcs) → tester once at arc close →
orchestrator closes on green numbers. `watcher` sits outside this line as an
ad-hoc context firewall.

## Tier Semantics

Tier controls pipeline depth and therefore cost. Default is `medium`.

| Tier | Pipeline | When |
| --- | --- | --- |
| `trivial` | `builder-trivial` (same edit across 5+ sites) or one `builder-fast` (a single scoped edit) → done. No planner. | Rename, typo, config tweak, single-line fix, doc edit; mass rename, bulk i18n/config |
| `medium` *(default)* | Orchestrator card → Finders/Researchers (parallel, if needed) → Builders (prove own DoD). **No Planner, Reviewer, or Tester.** Planner joins only if the task is ambiguous/architectural. | Small feature, scoped refactor, bug fix with tests |
| `full` | Planner brief → Finders → Builders (prove own DoD) → Reviewer diff-pass → Tester once at arc close → orchestrator closes on green numbers | Cross-cutting change, schema/migration, security-adjacent, high-stakes refactor |

- Never run `full` as a default — the user opts in for genuinely risky work.
- `trivial` must NOT fall through to `medium`; skipping Reviewer is the point.
- Ambiguous task → dispatch Planner at the inferred tier, but instruct it to ask
  a clarifying question BEFORE the orchestrator dispatches subordinates.

## Planning & the 2-Strike Rule

- Enter plan mode for any non-trivial task (3+ steps or architectural
  decisions). Write plans to `.localdev/workflow/todo.md` as cards with
  verifiable done criteria.
- If something goes sideways, STOP and re-plan — don't keep pushing.
- **2-strike rule**: after 2 failed approaches to the same problem, STOP. Do not
  try a 3rd. Dispatch an `auditor` to diagnose the root constraint, then re-plan
  from that constraint. Track strikes via the card's `Attempts` field.
- **Shared working tree = no git-state mutation.** With concurrent agents on one
  tree, NOBODY runs `git stash`/`pop`, `checkout`, `reset` — a stash silently
  reverts ALL teammates' uncommitted work. Every builder brief must carry this
  rule.

## Verification

- Never mark a task complete without proving it works — run tests, check logs,
  demonstrate correctness. For UI changes, verify rendering.
- Builders prove their own DoD; verification scope = DoD scope, no extra suites.
- Verify through the runtime path the user actually exercises, not proxy
  signals (SIGTERM ≠ quit handler, mocked entry points ≠ real wiring).
- **UNVERIFIED is a valid verdict**: if runtime verification is blocked, state
  the blocker — never imply success from inspection or mocked tests alone.
- "Implement X" is not done. "Implement X, verify Y, tests pass" is. If you
  can't check it, it's not done. Don't push validation work to the user.

## Exploration Flow

1. GitNexus first for code-graph questions — callers/callees, impact analysis,
   execution-flow discovery (MANDATORY when `.gitnexus/` exists).
2. context-mode for large searches, large files, logs, test output, or any
   command output likely to exceed a screenful.
3. `finder` (fast) for bounded source exploration remaining after graph/context
   queries.
4. Reasoning model for planning, design, review, and audit after the code map is
   condensed.

context7 is MANDATORY before asserting library/API/CLI behavior — never answer
from training memory. **MCP failure = tell the user, never silently degrade**:
report the exact tool + verbatim error immediately; label results built without
the tool **DEGRADED**. Use RTK for short shell commands where token-filtered
output helps.

## Task Ledger

`.localdev/workflow/todo.md` is a lightweight status board — open cards only.
Card format:

```markdown
# Todo

## [doing] <task title>
- Assignee: builder-fast
- Attempts: 1/2
- DoD: <verifiable done criteria>
- Deps: <other task title, or "none">
```

Status is one of `[todo]`, `[doing]`, `[blocked]`. `Attempts` ties into the
2-strike rule — increment per failed approach, `2/2` triggers an Auditor.
When a task completes, remove its card and append an entry to
`.localdev/workflow/done.md` instead. A legacy checkbox-brief `todo.md` is
migrated to cards inline on first touch, no separate tooling needed.

## Blockers, Handoffs, Known Issues, Done Log

- **Blockers**: ambiguity unresolvable from code, docs, tests, or git history →
  append to `.localdev/workflow/blockers.md` (context, blocker, what you need,
  files involved), stop the task, ask the user. Header must start with `## ` and
  a 4-digit year so hooks detect it. A `[blocked]` card in `todo.md` pairs with
  the full entry here.
- **Handoffs**: work continuing in another session → write
  `.localdev/workflow/handoffs/<task-name>.md` (status, next steps, open
  questions, files touched). Check this directory FIRST when resuming. On task
  completion, absorb its durable content (summary, decisions, links, files)
  into the `done.md` entry and delete the handoff file — it's scaffolding, not
  docs, and should never outlive its task.
- **Known issues**: persistent platform/dependency constraints → document in
  `docs/KNOWN_ISSUES.md` (status, workaround, affected files, reference). This is
  permanent, committed project knowledge.
- **Findings**: intra-session discoveries other agents need → append to
  `.localdev/workflow/findings.md`. Ephemeral; delete on session close.
  Findings *inform*; blockers *halt*.
- **Done log**: completed cards move to `.localdev/workflow/done.md` — a
  timestamped entry (`## YYYY-MM-DD HH:MM — <title>`) with summary, links, files,
  and attempts. Append-only, grows unbounded by design; never loaded into
  session context wholesale and never deleted at session close (unlike
  `findings.md`). Search it via context-mode FTS when you need history.
