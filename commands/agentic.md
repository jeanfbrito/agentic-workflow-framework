---
description: One-shot dispatch — reads project framework context, pre-warms the Planner, and runs the pipeline at the specified tier
argument-hint: [task description] [--tier=trivial|medium|full]
---

Dispatch the `planner` subagent to handle `$ARGUMENTS`. This is the front door for any non-trivial task. The tier flag controls pipeline depth — and therefore cost.

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

3. **Dispatch the `planner` subagent** with:
   - Task — the parsed task description.
   - Tier — resolved tier.
   - Context block — the pre-warmed summary.
   - Pipeline rule per tier:
     - `trivial` → Planner writes a 1–2 line brief, delegates to ONE `builder-trivial` (same edit across 5+ sites) or `builder-fast` (a single scoped edit). **Skip Finders, Researchers, Reviewer, Tester.**
     - `medium` → Planner → Finders/Researchers (parallel) → Builders. **Skip Reviewer, Tester.**
     - `full` → Full pipeline — Finders/Researchers → Builders → Reviewer → Tester → Planner approves.

4. **Run in background** so this chat stays free to answer blockers or steer mid-task.

# Rules

- `trivial` MUST NOT fall through to `medium` as a safety net. Skipping Reviewer is the point.
- Ambiguous task (2+ plausible interpretations): dispatch the Planner at the inferred tier, but instruct it to ask a clarifying question BEFORE dispatching subordinates.
- If the pre-warmed context surfaces an open handoff matching this task, fold it into the Planner's brief.
- If `.localdev/workflow/` does not exist in the current project, run `/init-agentic` first, then retry.
