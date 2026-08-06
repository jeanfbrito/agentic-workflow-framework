---
description: One-shot dispatch — reads project framework context and runs the pipeline at the specified tier (Planner joins only for ambiguous/architectural/risky-core work)
argument-hint: [task description] [--tier=trivial|medium|full]
---

Run the pipeline for `$ARGUMENTS`. This is the explicit front door for one-shot dispatch. The tier flag controls pipeline depth — and therefore cost.

# Steps

1. **Parse `$ARGUMENTS`**
   - Extract `--tier=trivial|medium|full` if present; strip it from the task description.
   - If `--tier` missing, infer:
     - `trivial` → rename, typo, config tweak, single-line fix, flag addition, doc edit.
     - `medium` (default for non-trivial) → feature with 3–6 steps, scoped refactor, bug fix with tests.
     - `full` → cross-cutting change, schema/migration, security-adjacent, high-stakes refactor.
   - Never default to `full`. The user opts in.

2. **Build the pre-warmed context block**. Read, if present:
   - `.localdev/workflow/handoffs/*.md` — open handoffs
   - `.localdev/workflow/blockers.md` — active blockers (canonical format, see `AGENTIC.md § Canonical entry formats`)
   - `.localdev/workflow/findings.md` — current session findings
   - `.localdev/workflow/todo.md` — current plan, if any
   - `docs/KNOWN_ISSUES.md`

   Assemble a compact summary: per file, a count + first relevant line. Do not paste full bodies.

3. **Route the brief** — the Planner joins only when the task earns it:
   - Task is genuinely ambiguous (2+ plausible interpretations), architectural, or risky-core (core physics/engine, schema/migration, security-adjacent), or `--tier=full` → **dispatch the `planner` subagent IN THE FOREGROUND** (`run_in_background: false`) with the task, tier, and context block. The Planner cannot dispatch other agents — it has no `Agent` tool. Its job is to produce the brief, a verifiable Definition of Done, and a per-tier dispatch plan, written to `.localdev/workflow/todo.md`. Foreground, never background: nothing can be dispatched until the brief exists, so backgrounding only adds stall risk for zero parallelism (AGENTIC.md § Execution).
   - Well-scoped task (shape already clear) → **skip the Planner**: write the `todo.md` card yourself (status `[todo]`, Assignee, Attempts `0/2`, DoD, Deps) and proceed. A planner round costs ~8 blocking minutes and adds nothing here.

4. **Execute the pipeline per tier** (main chat = orchestrator; builders prove their own DoD — run the checks, report numbers):
   - `trivial` → dispatch ONE `builder-trivial` (same edit across 5+ sites) or `builder-fast` (a single scoped edit). **Skip Finders, Researchers, Reviewer, Tester.**
   - `medium` → dispatch Finders/Researchers (parallel, if needed), then Builders. **Skip Reviewer, Tester.**
   - `full` → Finders/Researchers → Builders → Reviewer diff-pass → Tester once at arc close → close on green DoD numbers. **No Planner re-approval round** — the Planner re-enters only via the auditor/2-strike path or when a builder's result contradicts the brief.

   Dispatch foreground when a single agent carries the critical path; background only when 2+ agents genuinely run concurrently — completion is notification-driven, not polled (AGENTIC.md § Async dispatch).

# Rules

- `trivial` MUST NOT fall through to `medium` as a safety net. Skipping Reviewer is the point.
- Ambiguous task (2+ plausible interpretations): dispatch the Planner at the inferred tier, but instruct it to ask a clarifying question before the orchestrator dispatches subordinates.
- If the pre-warmed context surfaces an open handoff matching this task, fold it into the Planner's brief.
- If `.localdev/workflow/` does not exist in the current project, run `/init-agentic` first, then retry.
- At any tier, when a stage fans out to 3+ same-stage agents or the pipeline needs a multi-stage find→verify sweep, route it through the Workflow lane per AGENTIC.md § Async dispatch instead of hand-dispatching each one.
