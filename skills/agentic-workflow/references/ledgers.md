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
```

Track failed approaches in `Attempts`. At two failures, diagnose the root
constraint before implementing another approach. Update the card with the
resulting decision, rather than repeating the failed approach.

## Blockers

Record a missing decision or external dependency that prevents the task from
continuing in `blockers.md`, and mark the matching card `[blocked]`. Continue
independent work. Resolve ordinary implementation choices without a blocker.

```markdown
# Active Blockers

## YYYY-MM-DD HH:MM — <summary>
- Context: <task and current work>
- Blocker: <what cannot be resolved from available evidence>
- What I need: <decision or external change>
- Files involved: <paths>
```

The H2 date prefix is a parser contract: the SessionStart hook recognizes
`^## [0-9]{4}-`. Remove resolved blockers and update the matching card.

## Handoffs and Findings

When work will continue in another session, write `handoffs/<task-name>.md`:

```markdown
# <task>

## Status
<completed work and relevant decisions>

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
```

Keep the timestamped H2 format. `done.md` is append-only; search relevant history
instead of reading the entire log. When agents share a tree, the main thread
owns card and blocker edits. Serialize shared appends or use the installed
`ledger-append.sh` helper, which locks appends to `done.md` and `findings.md`.

## Hook Context

SessionStart supplies a limited digest of blockers, cards, and handoffs.
PreCompact snapshots in-flight cards; on resume inspect live agents before
dispatching replacement work. Stop audits ledger consistency and reports
advisory findings. These reminders are context, not a replacement for the user's
current task or proof that an implementation works.
