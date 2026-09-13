# Agentic Workflow Framework

Conventions for carrying engineering work through completion, with optional
delegation and continuity across sessions. Follow the user's current scope,
authorization, and runtime instructions; this framework adds no permissions.

## Operating Mode

Handle clear, bounded work directly. Use delegation when the user requests it
or the active environment authorizes it and an independent task would benefit.
File count alone does not justify a planner, subagent, or review round.
Keep the user's selected model; role configuration applies only to delegated work.

Choose enough structure for the task:

| Tier | Use |
| --- | --- |
| trivial | A small answer or edit. Work directly; no routine card or planning round. |
| medium | Work needing several steps or continuity. Keep a card with observable completion criteria and focused verification. |
| full | Architectural, risky, or cross-system work. Resolve material design choices, plan dependencies, and review the risky changes. |

`/agentic <task> --tier=trivial|medium|full` selects structure, not authorization
to delegate or perform external actions. Infer the tier when omitted. Existing
"do it yourself" and "off orchestrator" requests continue to disable delegation.

## Context and Decisions

Reuse context already available. For continuing work, read the relevant open
card and matching handoff. Consult blockers, findings, and
`docs/KNOWN_ISSUES.md` when they affect the task. Search historical `done.md`
entries only when needed; the append-only log can grow without bound.

Read enough source to understand the affected contract. Consult architecture
docs for boundaries, reference implementations for porting, and deployment docs
when preparing a deployment. A small edit does not require a repository survey.

Resolve ordinary implementation choices from the request and available evidence.
Ask when missing information materially changes the outcome or an action needs
authorization. Continue independent work while a required answer is pending.
Do not add a planning approval or repeat approval for an already authorized step.

## Completion and Evidence

Carry the requested work through implementation and the checks needed to make
the result usable and reviewable. Fix failures caused by the change and rerun
affected checks within existing authorization. Do not stop at the first patch
when running or inspecting the result is part of the request.

Choose verification from the project's actual commands and the affected behavior.
Use focused checks; broaden for an unresolved risk, integration boundary, or
explicit requirement. Reuse passing evidence until a relevant edit, failure,
contradiction, or request for independent verification justifies another run.

For process lifetime, IPC, global command resolution, and UI behavior, exercise
the real path when available. Distinguish source inspection, mocked tests, and
live verification. If a required check cannot run, report `UNVERIFIED`, the
reason, and what was checked; complete unaffected work before handing back.

After two failed approaches to the same problem, diagnose the root constraint
before trying another implementation. Record the failed approaches on an active
card. Use an auditor only when delegation is authorized and useful; otherwise
diagnose locally. This checkpoint does not require a routine user approval.

Stop when the requested outcome and its focused checks are complete. Report the
result, evidence, and remaining limitations. Do not commit or push unless asked.

## Tools

- Use GitNexus for indexed structural and impact questions. A missing or stale
  symbol is unknown impact; use a bounded source lookup to resolve the gap.
  Prose and configuration edits without symbol changes need no graph query.
- Use context-mode to process large searches, logs, and data. Use native tools
  for file edits, and RTK for supported short shell observations.
- Verify uncertain or version-sensitive API and CLI behavior with available
  primary documentation tools, such as context7 or official documentation.
- If a tool fails, report the exact tool and error, then use a permitted
  alternative when it can answer the question. State any remaining evidence gap.
  Tool availability does not justify adding an installer or changing permissions.

## Task-Specific Guidance

Read only the reference needed for the current workflow. Paths below are relative
to this file, in both the repository/plugin and the global `~/.claude` install.

- [Ledgers](skills/agentic-workflow/references/ledgers.md): creating or updating
  cards, handoffs, blockers, findings, and completion entries. Working state
  belongs in gitignored `.localdev/workflow/`; durable project constraints belong
  in `docs/KNOWN_ISSUES.md`. Durable memory changes require an explicit request.
- [Delegation](skills/agentic-workflow/references/delegation.md): when authorized
  work benefits from subagents, including ownership, retries, and process lifetime.
- `/init-agentic`: initialize project working state when it is needed.
- `/handoff`, `/blocker`, `/known-issue`: record the corresponding project state.
- `/qq`: answer a concise, read-only side question while preserving the main task.
