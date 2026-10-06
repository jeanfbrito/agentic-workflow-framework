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
- Verified: <live|test|type-check|UNVERIFIED> @ <short-sha>
```

Update `Verified` after each check run. Stop warns when its sha is not HEAD.
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

## Files touched
- <path>
```

`findings.md` holds temporary evidence other work needs. Preserve useful findings
in the matching handoff before cleanup; do not erase another active task's notes.
Persistent platform or dependency constraints belong in `docs/KNOWN_ISSUES.md`
with status, workaround, affected files, and a reference. These project files
do not authorize writing to a separate durable memory system.

## Completion

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
