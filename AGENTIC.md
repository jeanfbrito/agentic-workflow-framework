# Agentic Workflow Framework

Conventions for carrying engineering work through completion, with optional
delegation and continuity across sessions. Follow the user's current scope,
authorization, and runtime instructions. This framework adds no permissions.

## Operating Mode

Handle clear, bounded work directly. Use delegation when the user requests it
or the active environment authorizes it and an independent task would benefit.
File count alone does not justify a planner, subagent, or review round.
Keep the user's selected model. Role configuration applies only to delegated work.

Choose enough structure for the task:

| Tier | Use |
| --- | --- |
| trivial | A small answer or edit. Work directly, with no routine card or planning round. |
| medium | Work needing several steps or continuity. Keep a card with observable completion criteria and focused verification. |
| full | Architectural, risky, or cross-system work. Resolve material design choices, plan dependencies, and review the risky changes. |

When a skill or command defines steps, copy them into the todo list word for word
before task-specific items. A step you skip stays in the list as `skip: <reason>`.

`/agentic <task> --tier=trivial|medium|full` selects structure, not authorization
to delegate or perform external actions. Infer the tier when omitted. Existing
"do it yourself" and "off orchestrator" requests continue to disable delegation.

Cost follows tier. Each role already carries its model. `finder`, `watcher`,
`tester`, and `researcher` run on the cheapest tier. `reviewer` and
`builder-fast` run mid-tier. `builder-smart` is only for reasoning-heavy work.
Delegate through the role rather than a hand-configured agent call, so cost is
set once. Harness effort toggles (ultracode, effort levels) raise reasoning
depth for the current task. They do not change the tier and do not authorize a
multi-agent `Workflow` fan-out. A fan-out needs an explicit request in the
user's words. Reviewing a small diff is targeted searches plus at most one
`reviewer`, never a finder per risk dimension. Reach for a fan-out only when
the question cannot be held in one context.

## Context and Decisions

Reuse context already available. For continuing work, read the relevant open
card and matching handoff. Consult blockers, findings, and
`docs/KNOWN_ISSUES.md` when they affect the task. Search historical `done.md`
entries only when needed. The append-only log can grow without bound.

Read enough source to understand the affected contract. Consult architecture
docs for boundaries, reference implementations for porting, and deployment docs
when preparing a deployment. A small edit does not require a repository survey.

Resolve ordinary implementation choices from the request and available evidence.
Ask when missing information materially changes the outcome or an action needs
authorization. Before asking which approach to take, find out whether running
something answers it (behavior, timing, layout, output). If so, run it or build
a throwaway prototype and let the result decide. Keep questions for product or
preference calls no experiment settles. When code can answer a full-tier design
question, settle it with a prototype before reviewing the plan. A review of a
plan with no code behind it invents risks. Continue independent work while a
required answer is pending. Do not add a planning approval or repeat approval
for an already authorized step.

Read the request's register. A flat requirement is a constraint. A request
hedged with "in my opinion" or "I think" invites a counter-proposal when
evidence supports one. When the user states what they do not understand,
explain that mechanism in the report rather than assuming familiarity. An
explanation of how something works or why it matters is context, not a request.
Build what was asked and name an adjacent idea in one line of the report.

Changing an existing default is not an ordinary implementation choice. Keep the
current default and make new behavior opt-in unless the request changes it.

**Encode lessons in structure.** A correction or rule that repeats belongs in the
strongest mechanism that works. In order: architecture that removes the mistake,
a type, a lint or CI check whose error names the fix, a test, or a hook. Prove
the check fails on the real past mistake. Write prose only for judgment calls
nothing can check. Pair each prose rule with what enforces it when something does.

## Completion and Evidence

Carry the requested work through implementation and the checks needed to make
the result usable and reviewable. Fix failures caused by the change and rerun
affected checks within existing authorization. Do not stop at the first patch
when running or inspecting the result is part of the request.

Choose verification from the project's actual commands and the affected behavior.
Use focused checks. Broaden them for an unresolved risk, an integration
boundary, or an explicit requirement. Reuse passing evidence until a relevant
edit, failure, contradiction, or request for independent verification justifies
another run.

For process lifetime, IPC, global command resolution, and UI behavior, exercise
the real path when available. Try to break an interactive change: empty input,
double submit, reload. Prove a visual-only change (styling, layout, shader,
material) with a render or screenshot of the affected view. A test suite does
not see paint.

**Prove it works** on the real artifact, not a proxy or a self-report.
**Build the lever**: when work repeats across units or must be rechecked, write
the script, codemod, or check that does or proves it. Do not work by hand. The
reviewer reruns the tool instead of trusting the claim.

Distinguish source inspection, mocked tests, and live verification. Label each
claim in a report as measured, inferred, or a guess in the same sentence.
Settle whether something shipped or is ready from the primary artifact: the
release or tag object, the lines a job emitted, or API state. A prerelease and
the stable after it are different answers. The lines a job emitted are not the
script text it echoed into the log. If a required check cannot run, report `UNVERIFIED`, the reason,
and what was checked. Complete unaffected work before handing back.

When verification requires expensive setup (provisioning a machine, building a
desktop app, configuring a new environment), audit the change for likely
failure first. Report that risk before paying the setup cost.

After two failed approaches to the same problem, diagnose the root constraint
before trying another implementation. **Attack the premise**: write down the
one sentence every failed approach assumed, and test it before the next fix.
Revert code that a refuted hypothesis motivated. Do not keep it because it
"might help". Record the failed approaches on an active card. Use an auditor
only when delegation is authorized and useful. Otherwise, diagnose locally.
This checkpoint does not require a routine user approval.

Take an offered early exit as soon as its condition is met. If the request says
to stop and report on finding a simple fix, stop there rather than completing the
survey of alternatives.

An unattended or looped run (`/loop`, scheduled wakeups, "keep going overnight")
needs a done predicate that can pass or fail. A duration is not one. It also
needs an escape hatch. When truly stuck, stop and write up why. Do not
reinterpret the goal or relax the predicate.

Stop when the requested outcome and its focused checks are complete. Lead a
plan, audit, or review report with a short plain-language statement of the
problem and the proposed action, before the supporting detail. Report the
result, the tradeoff taken and what it gave up, evidence, and remaining
limitations. Do not commit or push unless asked.

When a report hands work back (a finished multi-step task or a blocker), start
with a numbered list of what the user must do. Put the most blocking item first. Give one action per item. Name what to do, where, and what to send back
(for example, "Log into Stripe, export the September refunds CSV, put it in
inbox/"). Never list a check you could run yourself. When nothing is needed,
say so in one line.

## Writing

Write English in Simplified Technical English with the `asd-ste100` skill.
Use strict mode for procedures, QA steps, error messages, tool descriptions,
and instructions to another agent. Use STE-flavored mode for reports, PR
descriptions, tickets, commit bodies, and docs. Before you show text that will
be public, run `~/.claude/skills/asd-ste100/scripts/ste-lint.py` on it. Fix
each hard finding, or say why it stays. If the skill is missing, install it
from `jeanfbrito/agent-skills`. Keep every hedge, because confidence is content.
Voice-led writing, such as blog posts, is out of scope.

## Tools

- Use GitNexus for indexed structural and impact questions. A missing or stale
  symbol is unknown impact. Use a bounded source lookup to resolve the gap.
  Prose and configuration edits without symbol changes need no graph query.
- Use context-mode to process large searches, logs, and data. Use native tools
  for file edits, and RTK for supported short shell observations.
- Look up uncertain or version-sensitive API and CLI behavior in primary
  documentation, such as context7 or the official docs.
- If a tool fails, report the exact tool and error. Then use a permitted
  alternative when it can answer the question. State any remaining evidence gap.
  Tool availability does not justify adding an installer or changing permissions.

## Task-Specific Guidance

Read only the reference needed for the current workflow. Paths below are relative
to this file, in both the repository/plugin and the global `~/.claude` install.

- [Ledgers](skills/agentic-workflow/references/ledgers.md): creating or updating
  cards, handoffs, blockers, findings, and completion entries. Working state
  belongs in gitignored `.localdev/workflow/`. Durable project constraints
  belong in `docs/KNOWN_ISSUES.md`. Durable memory changes require an explicit
  request.
- [Delegation](skills/agentic-workflow/references/delegation.md): when authorized
  work benefits from subagents, including ownership, retries, and process lifetime.
- `/init-agentic`: initialize project working state when it is needed.
- `/handoff`, `/blocker`, `/known-issue`: record the corresponding project state.
- `/qq`: answer a concise, read-only side question while preserving the main task.
