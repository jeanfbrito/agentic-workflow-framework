---
description: Append a decision blocker to .claude/mytasks/blockers.md in canonical format and halt the current task until the user resolves it
argument-hint: [short-summary]
---

Append a new decision blocker to `.claude/mytasks/blockers.md`, then STOP and ask the user.

# Canonical entry format

Every blocker entry starts with an H2 date-stamp header. The SessionStart hook matches `^## [0-9]{4}-`, so this exact shape MUST be used (see `AGENTIC.md § Canonical entry formats`):

```
## YYYY-MM-DD HH:MM — <summary>
- Context: <current task + what you were doing>
- Blocker: <what you cannot resolve from code, docs, or git history>
- What I need: <the decision you need from the user>
- Files involved: <path list>
```

# Steps

1. If `.claude/mytasks/blockers.md` does not exist, create it with a `# Active Blockers` header.
2. Append a new entry in the canonical format above. Use today's date and current time. Fill every field from the CURRENT session — do NOT fabricate. If a field is unknown, write `<unknown>`.
3. After writing, STOP working on the current task. Present the blocker to the user and ask for a decision.
4. When the user resolves it:
   - Remove that entry from `blockers.md` (leave other entries intact).
   - Continue the task with their decision applied.
