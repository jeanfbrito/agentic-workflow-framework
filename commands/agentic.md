---
description: Carry a task through completion with proportionate planning and project continuity.
argument-hint: [task description] [--tier=trivial|medium|full]
---

Complete `$ARGUMENTS` using the current installation's `AGENTIC.md`; reuse it
if already loaded. Extract an optional `--tier=trivial|medium|full` from the task.
Infer the tier from the work's ambiguity, risk, and continuity needs when omitted.

- `trivial`: handle the answer or small edit directly, without a routine card.
- `medium`: keep a card with observable completion criteria and focused checks.
- `full`: resolve material design decisions, plan dependencies, and review the
  risky changes. This tier does not require a fixed sequence of agents.

Reuse the relevant card, matching handoff, and available evidence. Consult other
workflow files only where they affect the task. If working state is needed and
absent, use `/init-agentic`; a small edit does not need initialization.

Resolve ordinary choices within the user's request and existing authorization.
Ask only for material missing decisions or additional authorization; continue
independent work while waiting. Neither this command nor a tier flag grants
permission for delegation or external actions.

Implement, run the focused checks, and fix failures caused by the requested
change. When running or inspecting the result is part of the request, complete
that work before returning. Delegate only when authorized and useful, following
the delegation reference linked from `AGENTIC.md`.

Close on the requested outcome and its evidence. Move a completed card to
`done.md` and retire its handoff. If a required check is blocked, report the
specific gap and complete unaffected work; do not present a partial result as
fully verified.
