---
description: Initialize project task ledgers and known-issue records while preserving existing content.
---

Initialize working state in the current project. Reuse the ledger formats linked
from `AGENTIC.md`; preserve existing non-empty files.

Create missing `.localdev/workflow/handoffs/`, `todo.md`, `done.md`,
`blockers.md`, and `findings.md` with their corresponding headings. Create
`docs/KNOWN_ISSUES.md` with a heading and an entry-format comment covering status,
workaround, affected files, and reference.

For a git repository, ensure `.localdev/` is ignored and check that
`docs/KNOWN_ISSUES.md` can be tracked. Report an existing ignore conflict rather
than rewriting unrelated ignore rules.

When a project test command is already discoverable from maintained scripts or
documentation, use that source for future completion criteria. Record a
non-obvious invocation only if it would otherwise need rediscovery. No test
runner or permission-mode change is part of ledger initialization.

Report created paths, existing paths, and any unresolved setup constraint.
Do not commit unless the user has also requested it.
