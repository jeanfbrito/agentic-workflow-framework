---
name: "agentic-workflow"
description: "Use automatically for non-trivial engineering work: multi-step tasks, changes across 2+ files, risky or cross-cutting refactors, debugging with unknown root cause, multi-session work, structured task ledgers, blockers, handoffs, known issues, and verification planning. Drives Orchestrator dispatch-by-default with planner/finder/researcher/builder/reviewer/tester/auditor/watcher subagents."
---

# Agentic Workflow

The complete doctrine lives in **AGENTIC.md** — single source of truth. This skill deliberately duplicates none of it.

1. **Global install (the common case)**: `~/.claude/CLAUDE.md` imports `@AGENTIC.md`, so the doctrine is ALREADY in your context. Follow it directly — do NOT re-read it.
2. **Plugin-only install**: if the doctrine is not in context, Read `~/.claude/AGENTIC.md`; if that file doesn't exist, Read `AGENTIC.md` from this plugin's root directory (two levels up from this skill).

Orientation only — every rule below is specified fully in the doctrine:

- **Orchestrator mode**: think, brief, dispatch — builders/finders/researchers/watchers do the work; do not Edit/Grep/WebFetch yourself.
- **Ledgers**: `.localdev/workflow/` (todo.md cards with DoD, done.md log, blockers.md, findings.md, handoffs/) + committed `docs/KNOWN_ISSUES.md`.
- **Tiers**: `trivial` / `medium` (default) / `full` — pipeline depth = cost.
- **Async dispatch**: foreground for a sole critical-path agent; notification-driven completion (no polling); permission prompts are the #1 stall cause; SendMessage continuation for retries; worktree isolation for overlapping builders; Workflow tool for 3+ agent fan-outs.
- **Verification**: builders prove their own DoD with targeted tests (narrowest scope, never the full suite unless the DoD names it); runtime path over proxies; UNVERIFIED is a valid verdict; 2-strike rule then auditor.
