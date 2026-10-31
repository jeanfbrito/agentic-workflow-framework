# Project Working State

Keep active work in `.localdev/workflow/`, with `.localdev/` gitignored. Reuse
existing entries for the current task; preserve unrelated work. A simple answer
or small edit needs no card. `/init-agentic` supplies the directory layout.

## Cards

`todo.md` contains open cards only. Use `[todo]`, `[doing]`, or `[blocked]`:

```markdown
# Todo

## [doing] <task title>
- Assignee: main-thread
- Attempts: 0/2
- DoD: <observable outcome and exact focused verification scope>
- Deps: none
- Evidence: <absolute manifest path, or none for a small single-scenario task>
- Requirements: <absolute original requirements path and SHA-256>
- Actions: <action | authorized/prohibited/not-requested/pending | source | scope, one row per action>
- Decisions/conflicts/owners: <manifest entries or explicit unresolved items>
- Verified: <live|test|type-check|UNVERIFIED> @ <short-sha>
```

For multi-scenario work, use the [evidence schema and checker](evidence.md).
Record each action separately: implementation, commit, push, PR state, comments, thread resolution, and merge.
Retain its source and scope. A closed PR does not cancel separately authorized commit or push actions.
`not-requested` is not a user prohibition. A manifest cannot authorize an action.
Keep the original requirements hash in the card before evidence collection.
Record scope changes as decisions without removing original scenario IDs.

Update `Verified` after each check run. Stop warns when its sha is not HEAD.
A matching SHA alone does not establish reusable evidence.
The manifest also checks relevant dirty content, exact command, runtime, environment, and log hashes.
Track failed approaches in `Attempts`. At two failures, diagnose the root
constraint before implementing another approach. Update the card with the
resulting decision, rather than repeating the failed approach.

## Blockers

Record a missing decision or external dependency that prevents the task from
continuing in `blockers.md`, and mark the matching card `[blocked]`. Keep doing
independent work. On reversible work, proceed on the stated default and say so.
Stop only when the action is irreversible or no safe default exists. Resolve
ordinary implementation choices without a blocker.

```markdown
# Active Blockers

## YYYY-MM-DD HH:MM — <summary>
- Context: <task and current work>
- Blocker: <what cannot be resolved from available evidence>
- What I need: <decision or external change>
- Default if no answer: <action>
- Files involved: <paths>
```

The H2 date prefix is a parser contract: the SessionStart hook recognizes
`^## [0-9]{4}-`. Remove resolved blockers and update the matching card.

## Pause / stop

When the user asks to stop, pause, hand off, or "how much until we can stop":

1. Land a verified checkpoint first (checks still pass; no half-applied change). Then write the handoff.
2. Flip `[doing]` → `[todo]` with a `Handoff:` path, or `[blocked]` plus a `blockers.md` entry. A leftover `[doing]` card gets ACTION REQUIRED.
3. Do not move the card to `done.md` unless its DoD actually passed.

"Write a handoff" then "don't leave work, finish it to keep stable" is one instruction: checkpoint, then hand off.

## Handoffs and Findings

When work will continue in another session, write `handoffs/<task-name>.md`:

```markdown
# <task>

## Status
<completed work and relevant decisions>
Verified: <live|test|type-check|UNVERIFIED> @ <short-sha>

## Next
- [ ] <next action>

## Open questions
<questions or None>

## Unpushed work
<each local branch with no remote copy, its worktree, and the backup path, or None>

## Files touched
- <path>
```

`findings.md` holds temporary evidence other work needs. Preserve useful findings
in the matching handoff before cleanup; do not erase another active task's notes.
Persistent platform or dependency constraints belong in `docs/KNOWN_ISSUES.md`
with status, workaround, affected files, and a reference. These project files
do not authorize writing to a separate durable memory system.

When work cannot leave the machine yet (an embargo, a security fix, a hold on
publishing), keep it on named local branches, not only in a loop or scratch
branch. Back up those branches with `git bundle create` to a folder outside
the repo, and refresh the bundle at each stop. The handoff lists each branch
and the bundle path under `Unpushed work`. Without that list, a cleanup such
as `worktree-gc` can remove the only copy.

## Completion

Use the original scope when reporting completion.
Run the evidence checker when the card has a manifest.
List each `UNVERIFIED` scenario and each approved exclusion explicitly.
Do not describe an incomplete original matrix as complete under a narrower title.
Separate measured identity facts from reported results and permission records.

Remove the completed card and append to `done.md`. Absorb useful content from the
task's handoff into the entry, then remove only that completed handoff.

```markdown
# Done

## YYYY-MM-DD HH:MM — <task title>
- Summary: <result and verification; explicit evidence gaps>
- Links: <PR, issue, commit, or none>
- Files: <key paths>
- Attempts: <number of failed approaches>
- Verified: <live|test|type-check|UNVERIFIED> @ <short-sha>
```

A card can name an external ticket (Jira, GitHub issue, Linear). Then move
that ticket to its done or QA state in the same step, when the user's rules
allow ticket transitions. Put the PR or commit in a link on the ticket. Otherwise
the tracker shows no progress. In one run the work closed 37 items, and all 75
of its tickets stayed in "To Do". When the rules require a draft first, list
the transitions in the report for approval.

Keep the timestamped H2 format. `done.md` is append-only; search relevant history
instead of reading the entire log. When agents share a tree, the main thread
owns card and blocker edits. Serialize shared appends or use the installed
`ledger-append.sh` helper, which locks appends to `done.md` and `findings.md`.

## Standing Orders

`standing.md` holds numbered standing orders, one per line. Add one when the user
repeats an instruction. Subagent briefs include the file's content.

## Decision Log

On full-tier or unattended runs, log one row per decision (a fork, pivot, revert,
or verified checkpoint) with an evidence pointer (sha, `file:line`, PR, path).
The command `ledger-append.sh decision <phase> <decision> <why> <evidence> <result>`
appends to `decisions.tsv`. Stop nags when an open `- Tier: full` card has no row this session.

## Hook Context

SessionStart supplies a limited digest of standing orders, blockers with their
defaults, cards, and handoffs.
PreCompact snapshots in-flight cards; on resume inspect live agents before
dispatching replacement work. Stop audits ledger consistency and reports
advisory findings. These reminders are context, not a replacement for the user's
current task or proof that an implementation works.
