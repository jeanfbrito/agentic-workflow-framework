---
name: "agentic-workflow"
description: "Manage task ledgers, handoffs, and authorized delegation for work spanning sessions or agents."
---

# Agentic Workflow

Use the framework for work that needs continuity or agent coordination. A small,
self-contained edit does not need a workflow pipeline.

Reuse `AGENTIC.md` if it is already in context. Otherwise read the copy belonging
to this installation: `../../AGENTIC.md` from the skill directory in a plugin or
source checkout; `~/.claude/AGENTIC.md` in a global install. Do not substitute an
unrelated global copy when using the plugin's own version.

Read [references/ledgers.md](references/ledgers.md) when recording or resuming
project work. Read [references/delegation.md](references/delegation.md) when
delegation is authorized and useful.
Read [references/evidence.md](references/evidence.md) for a delivery across scenarios or sessions.
Preserve the original scenario IDs, action permissions, decisions, conflicts, and owners.
Use `scripts/evidence.py check <manifest.json> --json` under `python3 -I` before reporting completion.
The checker checks recorded coverage and current identity. It does not grant permission or judge logs.
For final-head verification, use [publication evidence](references/publication-evidence.md).
Capture the final node and external dependencies before the run. Seal the result only when those identities still match.
Load only the relevant reference.

When the user asks to stop, pause, or "how much until we can stop": land a
verified checkpoint first, write `handoffs/<task>.md`, flip `[doing]` to
`[todo]` (or `[blocked]`). A leftover `[doing]` card gets ACTION REQUIRED.
Do not mark done unless the card's DoD actually passed.

Complete the requested outcome and focused checks under existing authorization.
Invoking this skill does not grant additional permissions or require delegation.
