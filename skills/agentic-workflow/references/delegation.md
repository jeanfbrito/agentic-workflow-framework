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
| builder-fast | Clear, scoped implementation and its focused proof. Independent briefs run in parallel. |
| builder-smart | A failed builder-fast attempt, reasoning-intensive algorithms and concurrency, or prose for a public repo. |
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
question and a search budget; builders need a verification budget: targeted
checks while iterating, one full-suite run at the end. Either returns partial
findings and the unresolved gap when its budget is exhausted. Avoid dumping
unrelated conversation history.

A brief carries these fields. Copy the block and fill it.

```
Outcome: <one sentence; the observable result>
Base: <repo, branch or commit, worktree yes/no>
Read first: <the project's agent guide, the card, the paths>
Setup: <the project's worktree or environment steps, in order>
Owns: <the files or folders this agent may write; nothing else>
Constraints: <locks, shared folders, commands that must not run, defaults that stay>
Actions: <independent action/status/source/scope records, without inferred permissions>
Evidence: <manifest path, original scenario IDs, requirements hash, owners and open conflicts>
Production command: <each check with the exact flags the real run uses>
Verification budget: <targeted checks while iterating; one full check at the end>
Time budget: <wall-clock; at the budget, stop and report partial work>
Report: changed paths; each check as "command -> result line" (the exact
command beside each PASS); unresolved issues; evidence gaps; proposed ledger
entries. No commits outside the owned paths; no attribution lines.
```

Keep each evidence result bound to its original scenario and complete source identity.
Use the [manifest checker](evidence.md) for multi-scenario work.
A worker's reported PASS does not establish the log's meaning or grant action permission.
Batch ready integrations before checks. Reuse evidence only when its exact identity still matches.

A check run with a changed flag, a smaller map or a default configuration is a
different check. The worker reports it as such, and the main thread does not
take it as the production result.

Workers share responsibility with other contributors. Preserve their edits.
Serialize overlapping write scopes, or use real isolated worktrees if the
runtime supports them. On a shared tree, do not stash, reset, checkout, or run
other git operations that can overwrite another worker's changes. Isolation
does not authorize committing, pushing, or changing files outside the assignment.
The main thread owns task-state decisions; workers return proposed ledger entries.

## Dispatch and Continuation

Dispatch independent subagent work at the same time by default. The user does
not need to ask. Read-only scouts (finder, researcher) can always run together.
Testers and watchers run together when their commands do not share ports,
build output, or other state. Builders run together when their write scopes do
not overlap. A split job finishes sooner on cheap workers, although each worker
needs more turns than a stronger model would. Use an isolated worktree for each
writer when the runtime supports it and the project can run its checks there.
Otherwise keep the write scopes separate on the shared tree. Keep a small task
local, and keep a sequential critical path on one agent. If the runtime
supports foreground dispatch, prefer it for a sole critical-path agent. Use the
active runtime's actual tool schema. Claude-specific flags and
message behavior are not portable to other runtimes.

Completion is notification-driven. Wait using the available runtime tool when
no independent work remains; avoid repeated polling. Reuse the same agent for
follow-ups and failure diagnosis when its context remains useful. Confirm how
that runtime resumes an idle agent instead of assuming a message starts a turn.

Each brief carries a time budget. A worker that reaches it stops. It lands what
passes and reports the rest as partial. When the budget passes without a report,
the main thread sends a stop order. The order names what to keep. It asks for
the report within minutes. Merge the work that passed its checks. Carry
the rest as a card. A worker that runs for hours without a report is a stall,
not progress.

`builder-smart` also has a hard turn cap (`maxTurns` in its frontmatter). Each
turn reads the full context again, so a long run costs more for each turn than
a short run. When a worker stops at its cap, send it one message: land what
passes, then report. Give the rest of the work to a new worker with a smaller
brief. Do not resume the worker to continue, because the resumed worker keeps
its full context.

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

A worker stops or kills only a process that it started. A worker can need to
stop another process, such as a dev app, a debug port or a test server. Then
first find which agent uses that process, with `lsof -i :<port>` or the
process's parent. When
another agent uses it, wait for that agent to end. In one run a demo agent
was told to quit the dev app on a shared debug port. It killed the app of a
running loop cycle, and that cycle lost its live check.

Do not merge into a tree that a running process reads. Do not edit its scripts
either. A runtime that loads scripts lazily mixes the versions, and the run
fails with errors that the settled tree does not have. Wait for the run
to end, or run it in a worktree.

Match the waiting mechanism to the length of the wait. A watcher suits a job that
finishes within the attention it can hold; on a multi-minute remote wait such as
CI it tends to return early while reporting that it is still monitoring. Run
those from the main thread as a backgrounded command that exits on completion —
`gh run watch <id> --exit-status` for a GitHub Actions run — and let the exit
notification arrive.

For larger fan-outs, make dependencies and result formats explicit. Use a
Workflow tool only if it exists and its use is authorized: the user asked for
it, or ultracode is on for the session. No fan-out threshold is an automatic
opt-in.

Return changed paths, checks and outcomes, unresolved issues, and evidence gaps.
Quote the exact command beside each PASS line. A PASS from a simpler
configuration (a default flag, a smaller map, a stub) is not the result. The
main thread reruns each check with the production flags before it merges. It
skips the rerun when the worker ran the same command on the same commit. It
integrates every ready branch first and reruns one time for the batch. Then
it integrates the result, completes the remaining requested work, and closes
the task once its completion criteria are met.
