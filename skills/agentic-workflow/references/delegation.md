# Authorized Delegation

Use subagents only within the active environment's authorization. A skill,
task tier, or number of files does not grant permission. Keep work local when
delegation adds more coordination than useful independent work.

## Choosing a Role

Use the installed role's model and tool configuration; do not change the main
conversation's selected model. Read a role prompt only when using that role.

| Role | Useful for |
| --- | --- |
| planner | Material architectural ambiguity or risky design decisions; returns a brief, without coding or delegation. |
| builder-fast | Clear, scoped implementation and its focused proof. |
| builder-smart | A failed ordinary implementation or reasoning-intensive algorithms and concurrency. |
| builder-trivial | A fully specified repetitive transformation. |
| finder | Bounded, read-only code location and call-chain questions. |
| researcher | Primary-source API, library, CLI, and platform research. |
| reviewer | Independent judgment on a risky diff. |
| tester | Combined integration checks, unavailable builder proof, or requested independent validation. |
| auditor | Root-constraint diagnosis after repeated failures. |
| watcher | A finite noisy command or a bounded logfile digest. |

These roles are options, not a pipeline every task must traverse. Reuse a
builder's passing evidence. Add independent review or testing for a specific
risk or request, rather than automatically repeating each card's checks.

## Briefs and Ownership

Give the agent a concrete outcome, known paths or graph query, file ownership,
constraints, focused verification, and an output shape. Scouts need a bounded
question and a search budget; return partial findings and the unresolved gap
when the budget is exhausted. Avoid dumping unrelated conversation history.

Workers share responsibility with other contributors. Preserve their edits.
Serialize overlapping write scopes, or use real isolated worktrees if the
runtime supports them. On a shared tree, do not stash, reset, checkout, or run
other git operations that can overwrite another worker's changes. Isolation
does not authorize committing, pushing, or changing files outside the assignment.
The main thread owns task-state decisions; workers return proposed ledger entries.

## Dispatch and Continuation

Run independent work concurrently only when useful local work or another agent
can proceed beside it. If the runtime supports foreground dispatch, prefer it
for a sole critical-path agent. Use the active runtime's actual tool schema;
Claude-specific flags and message behavior are not portable to other runtimes.

Completion is notification-driven. Wait using the available runtime tool when
no independent work remains; avoid repeated polling. Reuse the same agent for
follow-ups and failure diagnosis when its context remains useful. Confirm how
that runtime resumes an idle agent instead of assuming a message starts a turn.

For a stall, check the task's actual state, including pending permission requests,
then make one bounded probe or narrow the brief. A past permission incident is
not proof of the current cause. Never install blanket permissions to bypass a
stall. Keep work foreground/local if approvals cannot surface in the background.

After two failed approaches, diagnose before another implementation. Use an
auditor when useful and authorized. Escalate model capability only when the
evidence points to it as the constraint.

## Processes and Results

The main thread owns long-lived servers in a process session that survives
agent completion. A watcher handles finite jobs or logfile digests; it does not
own server lifetime or poll other agents. Preserve a requested running server.

For larger fan-outs, make dependencies and result formats explicit. Use a
Workflow tool only if it exists and its use is authorized; no fan-out threshold
constitutes an automatic tool opt-in.

Return changed paths, checks and outcomes, unresolved issues, and evidence gaps.
The main thread integrates the result, completes remaining requested work, and
closes the task once its completion criteria are met.
