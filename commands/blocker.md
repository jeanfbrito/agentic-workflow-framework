---
description: Append a decision blocker to .localdev/workflow/blockers.md in canonical format, with the default action to take if no answer arrives.
argument-hint: [short-summary]
---

Append a new decision blocker to `.localdev/workflow/blockers.md`, then ask the user and keep doing independent work.

# Canonical entry format

Every blocker entry starts with an H2 date-stamp header. The SessionStart hook matches `^## [0-9]{4}-`, so this exact shape MUST be used (see `skills/agentic-workflow/references/ledgers.md § Blockers`):

```
## YYYY-MM-DD HH:MM — <summary>
- Context: <current task + what you were doing>
- Blocker: <what you cannot resolve from code, docs, or git history>
- What I need: <the decision you need from the user>
- Default if no answer: <the action you take if no answer arrives>
- Files involved: <path list>
```

# Steps

1. If `.localdev/workflow/blockers.md` does not exist, create it with a `# Active Blockers` header.
2. Append a new entry in the canonical format above. Use today's date and current time. Fill every field from the CURRENT session — do NOT fabricate. If a field is unknown, write `<unknown>`.
3. After writing, present the blocker to the user and ask for a decision. Keep doing independent work. For reversible work, proceed on the stated default and say so. Stop only when the action is irreversible or no safe default exists.
4. When the user resolves it:
   - Remove that entry from `blockers.md` (leave other entries intact).
   - Continue the task with their decision applied, reverting any default-based work it overrides.
