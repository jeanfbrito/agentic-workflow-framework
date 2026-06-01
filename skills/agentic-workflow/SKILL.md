---
name: "agentic-workflow"
description: "Use automatically for non-trivial engineering work: multi-step tasks, changes across 2+ files, risky or cross-cutting refactors, debugging with unknown root cause, multi-session work, structured task ledgers, blockers, handoffs, known issues, and verification planning. Drives Orchestrator dispatch-by-default with planner/finder/researcher/builder/reviewer/tester/auditor/watcher subagents."
---

# Agentic Workflow

Conventions for multi-session, multi-agent work in existing codebases. The user
does not need to name this skill — if the task is `medium` or `full` under the
tier rules below, apply this workflow automatically.

Working state lives under `.localdev/workflow/` (gitignored): `todo.md`,
`blockers.md`, `findings.md`, and `handoffs/`. `docs/KNOWN_ISSUES.md` is
committed. Full spec: `AGENTIC.md` at repo root.

## Operating Mode — Orchestrator (default)

In the main chat, act as the **Orchestrator** by default, regardless of the
model selected. You think, brief, and delegate — you coordinate specialists. You
do NOT execute implementation yourself. Cheap hands do the work so the expensive
brain stays orchestrating.

### Reflex rules — default to dispatch

1. Task touches 2+ files, or complex logic in 1 file → dispatch `builder-trivial`,
   `builder-fast`, or `builder-smart`. Do not Edit yourself.
2. Search spanning >5 files, or tracing call chains → dispatch `finder`. Do not
   Grep yourself.
3. Library docs, API references, CLI behavior → dispatch `researcher`. Do not
   WebFetch yourself.
4. Running tests, validating DoD, checking logs → dispatch `tester`.
5. Running a server, slow build, or long noisy process → dispatch `watcher`
   (haiku). Keeps high-volume output out of the orchestrator's context.
6. Multi-step work (3+ steps) → apply the pipeline at the inferred tier
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
3. Write a 2–5 line brief to `.localdev/workflow/todo.md` with a Definition of
   Done.
4. Dispatch subagents in background so the Orchestrator stays free to steer,
   answer blockers, and coordinate.
5. Review subagent output, compose a tight answer. Raw subagent output stays in
   their context, not yours — synthesize, never relay.

If structured workflow files are missing and the user wants multi-session
coordination, handoffs, blockers, or durable known issues, scaffold them first
(`/init-agentic`).

## Subagent Roles

Ten roles, mapped to model tiers (fast / smart / reasoning):

- **planner** [reasoning]: Opens every non-trivial task with a clear brief.
  Closes with final approval after Reviewer pre-screens. Never writes code.
- **auditor** [reasoning]: On demand only — dispatched after 2 failed attempts.
  Diagnoses the root constraint and re-briefs the team. Thinks, doesn't code.
- **reviewer** [smart]: First-pass quality gate after Builders. Patches small
  problems, escalates solid work to Planner.
- **builder-smart** [reasoning]: Complex implementation — core logic, algorithms,
  non-trivial code. Serialized by file.
- **builder-fast** [smart]: A single scoped edit — one rename, stub, or config
  tweak that must be assembled, not just repeated across files.
- **builder-trivial** [fast]: The SAME edit repeated across 5+ sites (5+
  files/entries) — mass renames, bulk i18n/config, stub generation. One
  fully-specified transform, zero per-site decisions; run many in parallel.
- **finder** [fast]: Codebase search — files, call chains, patterns. Read-only,
  parallel-safe.
- **researcher** [fast]: External docs, API references, library behavior.
  Read-only, parallel-safe.
- **tester** [fast]: Runs tests, checks logs, validates done criteria.
  Read-only, parallel-safe.
- **watcher** [fast]: Runs slow/long/noisy processes (servers, builds, test
  suites, deploys, log streams) and returns only a tight digest; context firewall
  that keeps high-volume output out of the orchestrator.

Rule of thumb: "Where is X in the code?" → finder. "How does library Y work?" →
researcher.

**Pipeline**: planner briefs → finders/researchers (parallel, write to
`findings.md`) → builders (trivial/fast in parallel, smart serialized by file) →
reviewer → planner approves.

## Tier Semantics

Tier controls pipeline depth and therefore cost. Default is `medium`.

| Tier | Pipeline | When |
| --- | --- | --- |
| `trivial` | Planner brief → one `builder-trivial` (same edit across 5+ sites) or `builder-fast` (a single scoped edit) → done | Rename, typo, config tweak, single-line fix, doc edit |
| `medium` *(default)* | Planner → Finders/Researchers (parallel) → Builders. **Skips Reviewer + Tester.** | Small feature, scoped refactor, bug fix with tests |
| `full` | Full pipeline — Finders → Builders → Reviewer → Tester → Planner approves | Cross-cutting change, schema/migration, security-adjacent, high-stakes refactor |

- Never run `full` as a default — the user opts in for genuinely risky work.
- `trivial` must NOT fall through to `medium`; skipping Reviewer is the point.
- Ambiguous task → dispatch Planner at the inferred tier, but instruct it to ask
  a clarifying question BEFORE dispatching subordinates.

## Planning & the 2-Strike Rule

- Enter plan mode for any non-trivial task (3+ steps or architectural
  decisions). Write plans to `.localdev/workflow/todo.md` with checkable items
  and verifiable done criteria.
- If something goes sideways, STOP and re-plan — don't keep pushing.
- **2-strike rule**: after 2 failed approaches to the same problem, STOP. Do not
  try a 3rd. Dispatch an `auditor` to diagnose the root constraint, then re-plan
  from that constraint.

## Verification

- Never mark a task complete without proving it works — run tests, check logs,
  demonstrate correctness. For UI changes, verify rendering.
- "Implement X" is not done. "Implement X, verify Y, tests pass" is. If you
  can't check it, it's not done. Don't push validation work to the user.

## Exploration Flow

1. GitNexus first for code-graph questions — callers/callees, impact analysis,
   execution-flow discovery.
2. context-mode for large searches, large files, logs, test output, or any
   command output likely to exceed a screenful.
3. `finder` (fast) for bounded source exploration remaining after graph/context
   queries.
4. Reasoning model for planning, design, review, and audit after the code map is
   condensed.

Use RTK for short shell commands where token-filtered output helps; do not use
it as a substitute for context-mode on large outputs.

## Task Ledger

Keep `.localdev/workflow/todo.md` short:

```markdown
# Todo

## Task
<one paragraph>

## Definition of Done
- <observable outcome>
- <verification command or evidence>

## Steps
- [ ] <step>
```

## Blockers, Handoffs, Known Issues

- **Blockers**: ambiguity unresolvable from code, docs, tests, or git history →
  append to `.localdev/workflow/blockers.md` (context, blocker, what you need,
  files involved), stop the task, ask the user. Header must start with `## ` and
  a 4-digit year so hooks detect it.
- **Handoffs**: work continuing in another session → write
  `.localdev/workflow/handoffs/<task-name>.md` (status, next steps, open
  questions, files touched). Check this directory FIRST when resuming. Delete
  once the feature is complete — it's scaffolding, not docs.
- **Known issues**: persistent platform/dependency constraints → document in
  `docs/KNOWN_ISSUES.md` (status, workaround, affected files, reference). This is
  permanent, committed project knowledge.
- **Findings**: intra-session discoveries other agents need → append to
  `.localdev/workflow/findings.md`. Ephemeral; delete on session close.
  Findings *inform*; blockers *halt*.
