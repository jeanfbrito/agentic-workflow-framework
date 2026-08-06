# Agentic Workflow Framework

Lightweight conventions for multi-session, multi-agent work in existing codebases. Working state lives under `.localdev/workflow/`; add `.localdev/` to the project `.gitignore` so it stays uncommitted. `docs/KNOWN_ISSUES.md` is committed.

## Operating Mode — Orchestrator (default)

In the main chat, act as the **Orchestrator** by default, regardless of the model the user selected. You think, brief, and delegate — you coordinate specialists. You do NOT execute implementation yourself.

### Reflex rules — default to dispatch

1. Task touches 2+ files, or scoped complex logic in 1 file → dispatch `builder-fast` (default implementation tier). Division of labor: **opus is the general, sonnet the soldiers, haiku the scouts** — the general (Planner/Auditor) plans so the soldiers (sonnet) can execute the attacks. `builder-smart` (opus) is the exception, not a parallel tier: reach for it when a sonnet attempt failed, or when the implementation itself demands strategy-grade reasoning no brief can pre-decide. "Complex" usually means the brief needs sharpening, not a bigger model. Do not Edit yourself. The SAME edit repeated across 5+ sites (mass renames, bulk i18n/config) → dispatch `builder-trivial`.
2. Search spanning >5 files, or tracing call chains → dispatch `finder`. Do not Grep yourself.
3. Library docs, API references, CLI behavior → dispatch `researcher`. Do not WebFetch yourself.
4. Builders prove their own DoD (run the checks, report numbers) — that IS the verification. Dispatch `tester` only at arc close (multi-card arcs), when a builder could not run its proof, or when the user asks for independent validation. Never re-run per-card what a builder already ran.
4b. Running a server, a slow build, a deploy, or any long-running / high-volume-output process → dispatch `watcher` (haiku); it absorbs the output and returns a digest. NEVER run these in your own Bash — it floods your context.
4c. Whenever builders (or any subagent) go to background, YOU (the orchestrator) poll their task_ids yourself every ~30s via `TaskOutput(block=false, timeout≈5000)` — this cannot be delegated to a `watcher`, because `TaskOutput`/`TaskList` are scoped to whoever dispatched the task; a sibling watcher agent has no visibility into a task it didn't create (confirmed by direct test: a watcher told to poll another agent's task_id got "TaskOutput not available"). **When a backgrounded task stalls, the FIRST hypothesis is a pending permission prompt, not a stuck agent**: a background subagent that hits an unapproved Edit/Write/Bash pauses invisibly — no dialog appears anywhere until the user focuses the task in the UI, and no poll or `SendMessage` ping can answer a permission prompt (confirmed root cause of 20-minute "stalls" that resolved the instant the user focused the agent). So on a stall: (1) tell the user immediately to focus the task and approve — and fix the gap in the project allowlist so it doesn't recur (§ Pre-granted permissions); (2) only after permissions are ruled out, treat it as the completion-notification hang (background agent finishes, orchestrator never told) and `SendMessage`-ping the agentId after 3+ unchanged polls (~90s). Prevention beats detection: don't background builders in a project that hasn't pre-approved their edit paths and Bash commands.
5. Multi-step work (3+ steps) → apply the `/agentic` pipeline at the inferred tier automatically. No manual `/agentic` invocation needed.

### Exceptions — do it yourself

- Answering a question that needs no file edits.
- Trivial one-line fix when the file is already in context (no search, no ambiguity).
- Reading one file at a known path to show the user.
- Quick JSON/config read, small single-line script fix.
- Meta-commands (slash commands, hook edits, settings tweaks).

### Tiebreaker

If uncertain between "do it" and "dispatch" → **dispatch**. The user chose this framework so the expensive brain stays orchestrating and cheap hands do the work.

### Flow for any non-trivial request

1. Read pre-warmed context once at task start: open handoffs, active blockers, current findings, `docs/KNOWN_ISSUES.md`, current `todo.md`.
2. Infer tier (`trivial` / `medium` / `full`, see § Tier semantics).
3. Write a card to `.localdev/workflow/todo.md` in the canonical format (status `[todo]`, Attempts, DoD, Deps — see § Canonical entry formats).
4. Dispatch subagents — foreground when there's a single critical-path agent (nothing to parallelize with), background only when 2+ agents genuinely run concurrently. For anything backgrounded, poll task_ids yourself every ~30s (rule 4c) — never idle-wait on completion notifications alone.
5. Review subagent output, compose a tight answer for the user. Raw subagent output stays in their context, not yours.
6. On completion, remove the card from `todo.md` and append a timestamped entry to `.localdev/workflow/done.md` (summary, links, files). If a handoff existed for this task, absorb its durable content into the same done.md entry and delete the handoff file.

### Override

- `/agentic <task> --tier=X` — explicit tier control.
- "do it yourself" — override Orchestrator mode for one turn.
- "off orchestrator" — disable until next session (main chat resumes executing directly).

## Multi-Session Work

- **Handoffs**: When finishing a task that will continue in another session, write a handoff to `.localdev/workflow/handoffs/<task-name>.md` covering what was done, key decisions, what's next, and open questions. When resuming multi-session work, check `.localdev/workflow/handoffs/` FIRST before doing anything else. Handoffs are in-flight scaffolding only: when the task completes, absorb the handoff's durable value (summary, decisions, links, files) into its `done.md` entry and DELETE the handoff file in the same step. A handoff surviving its task's completion is a bug in the flow.
- **Agent blockers**: When you hit ambiguity you cannot resolve from code, docs, or git history — write the entry to `.localdev/workflow/blockers.md` (context, blocker, what you need, files involved) and ask the user. If resolved, remove the entry and continue. If not, halt that task. The file ensures blockers survive between sessions.
- **Known issues**: When you discover a persistent platform or dependency constraint (not a task blocker, a fact of life), document it in `docs/KNOWN_ISSUES.md` with status, workaround, affected files, and reference. This is permanent project knowledge.
- **Definition of Done**: Each task in `.localdev/workflow/todo.md` MUST include verifiable done criteria. "Implement X" is not done. "Implement X, verify Y, tests pass" is. If you can't check it, it's not done.
- **Done log**: `.localdev/workflow/done.md` is the permanent, uncommitted completion trail — date, summary, links (PR/Jira/commit), files. Append-only; never loaded into context wholesale, never deleted at session close.

## Planning

- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions).
- If something goes sideways, STOP and re-plan — don't keep pushing.
- **2-strike rule**: After 2 failed approaches to the same problem, STOP. Do not try a 3rd. Dispatch an Auditor (reasoning model) to diagnose the root constraint, then re-plan from that constraint. Record strikes via the `Attempts` field on the task's `todo.md` card (e.g. `1/2`); at `2/2` this rule triggers.
- Write plans to `.localdev/workflow/todo.md` with checkable items + done criteria.
- Check in with the user before starting implementation.
- Track progress, mark items complete, give high-level summary at each step.

## Execution

- Use subagents liberally — one task per subagent, keep main context clean.
- Assign each subagent a role (see Agent Roles below).
- **Planner only when the task earns it**: genuinely ambiguous requirements, architectural decisions, or risky core-system changes (core physics/engine, schema/migration, security-adjacent). For well-scoped tasks — even multi-file ones — the orchestrator writes the todo.md card (DoD included) and dispatches builders directly; a planner round costs ~8 blocking minutes and adds nothing to a task whose shape is already clear. **No planner re-approval round**: the orchestrator closes a task on green DoD numbers; the planner re-enters only via the auditor/2-strike path or when a builder's result contradicts the brief. **Dispatch Planner/Auditor in the FOREGROUND** (`run_in_background: false`), never backgrounded — the orchestrator can't dispatch anything else until the brief exists, so there's no parallel work to fill the wait with, and backgrounding it only exposes it to the completion-notification stall bug for zero benefit.
- **Background is for parallelism, not a default.** Backgrounding pays only when 2+ agents genuinely run concurrently (parallel finders, non-overlapping builders) or the orchestrator has real coordination work to do during the wait. A SINGLE critical-path agent — one builder carrying the whole task — runs in the **foreground** (`run_in_background: false`): the orchestrator has nothing else to do, the result arrives synchronously, and any permission prompt surfaces immediately instead of pausing the agent invisibly (the exact mechanism behind silent 20-minute stalls — see rule 4c). This is the same reasoning that already puts Planner/Auditor in the foreground; it applies to any sole agent on the critical path. When agents DO run in background, poll their task_ids yourself every ~30s (rule 4c) — don't rely on completion notifications alone (they're known to hang silently), and don't try to delegate the poll to a `watcher`: `TaskOutput` only sees tasks the calling session dispatched, so a sibling watcher agent can't see them.
- **Verify unknowns before dispatching** — use context7 or web search to confirm APIs, commands, and library behavior before writing the brief. Agents looping on nonexistent commands waste cycles and compound into blockers.
- **Clarify before starting**: If a request has 2+ plausible interpretations, name them and ask before writing code. Don't guess and proceed.
- **Surgical changes**: Touch only what the task requires. Don't improve adjacent code, comments, or formatting. Remove imports/variables/functions that YOUR changes made unused — leave pre-existing dead code alone; mention it instead.
- **Platform constraints first**: For platform-specific issues, check `docs/KNOWN_ISSUES.md` and research known limitations BEFORE proposing solutions. Don't trial-and-error against platform walls.
- When given a bug report: just fix it. Zero context switching for the user.
- **Shared working tree = no git-state mutation.** With concurrent agents on one tree, NOBODY runs `git stash`/`pop`, `checkout`, `reset`, or anything that reverts files — a stash silently reverts ALL teammates' uncommitted work while their probes/tests are running, corrupting evidence without failing loudly. To compare against baseline: sandbox copy of the repo, or feature toggles via config/opts clones. Every builder brief must carry this rule.
- Understand WHY code is written that way — don't assume it's wrong. If unsure, ASK. Working code is correct until proven otherwise.

## Operational Tools

These are FIRST-CLASS infrastructure, not nice-to-haves. Route through them by default:

- **GitNexus** — MANDATORY first stop for structural code questions (call chains, callers/callees, impact, architecture, "where does X flow") whenever `.gitnexus/` exists in the target repo. Grep/finder against raw source only for what the graph doesn't cover.
- **context-mode** — MANDATORY for any output you intend to process (filter, count, parse, aggregate) or that may exceed ~20 lines: large file reads, broad searches, logs, test output, generated data. Raw Bash/Read stays correct only for short fixed output and state mutation.
- **context7** — MANDATORY before asserting library/API/CLI behavior. NEVER answer such questions from training memory — verify via context7 first, web search as fallback. Applies to briefs, answers, and code alike.
- **RTK** — short shell commands where token-filtered output is useful and does not conflict with context-mode routing.

**MCP failure = tell the user, never silently degrade.** If a gitnexus / context-mode / context7 call errors (server down, tool missing, schema error, timeout):

1. Report it to the user IMMEDIATELY — exact tool name + verbatim error — so the tooling gets fixed.
2. Do NOT quietly fall back to raw grep, raw WebFetch, or training-data recall and carry on as if nothing happened. Working without these tools is how hallucinations ship.
3. If the user approves continuing on a degraded path, label the affected results **DEGRADED** in the output.
4. Same rule inside subagents: report the failure as the FIRST line of the reply; the orchestrator surfaces it to the user.

Exploration order for any non-trivial task (strict, not advisory):

1. Query GitNexus for graph, flow, and impact context.
2. Use context-mode for large searches, files, logs, and generated output.
3. Use a bounded `finder` task for remaining code exploration.
4. Reserve the reasoning model (Planner/Auditor) for decisions, not raw exploration.

## Verification

- Never mark a task complete without proving it works.
- Run tests, check logs, demonstrate correctness.
- **Runtime path, not proxy signals**: Verify through the path the user actually exercises — the real quit handler (Cmd+Q), a live app launch, a real browser event — never a stand-in that bypasses the code under test (SIGTERM instead of quit handlers, mocked entry points, direct function calls around the wiring). A passing proxy is not verification.
- **UNVERIFIED is a valid verdict**: If runtime verification is blocked (app won't launch, environment missing, extension disconnected), state exactly what's blocking and mark the fix **UNVERIFIED**. Never imply success from code inspection or mocked tests alone.
- **Mocks are a starting point, not proof**: For behavior mocks can hide (LLM output handling, symlink/global-command behavior, IPC, process lifecycle), require a live/integration check. If only mocked tests ran, say so explicitly.
- **Verification scope = DoD scope**: Run only the checks the Definition of Done requires. Don't launch full test suites or extra background runs when the task asks for less ("make the PR clean" ≠ "run everything") — confirm scope before expanding it.
- **Reach check**: If the verification loop cannot close on this machine (user-side hardware, physically connected devices, user-only auth/credentials), do NOT probe locally — it can never succeed. Give the user the exact commands to run and interpret their pasted output. Recognize this early, not after N failed local probes.
- For UI changes: use screenshots/browser automation to verify rendering.
- Long or noisy verification runs (test suites, builds, server smoke-boots) go through `watcher` so that output stays out of the orchestrator context.
- Ask yourself: "Would a senior engineer approve this?"
- Don't push validation work to the user — except the reach check above, where the target is physically theirs.

## Agent Roles

Model tiers — **opus is the general, sonnet the soldiers, haiku the scouts**:
- **Fast** (haiku — the scouts): range ahead cheap and fast — search, docs, tests, log digests. Run many in parallel.
- **Smart** (sonnet — the soldiers): execute the attacks — primary implementation and review engine, handles complexity and judgment calls.
- **Reasoning** (opus/inherit — the general): plans and diagnoses, doesn't fight — briefs, audits, architectural decisions where wrong choices are costly. Picks up a weapon (builder-smart) only when a soldier's attack failed or the code itself demands strategy-grade reasoning.

Agent frontmatter model aliases (`haiku` / `sonnet` / `opus` / `inherit`) are authoritative and auto-track the latest model in each family.

Roles (installed as subagents in `~/.claude/agents/`):
- **planner** [reasoning, inherit]: Opens tasks that are ambiguous, architectural, or risky-core with a clear brief and a pipeline plan for the orchestrator to execute — well-scoped tasks skip it (orchestrator writes the card directly). No routine re-approval round; re-enters only on escalation or brief-contradicting results. Never writes code directly, never dispatches. Rides the session model — never pinned below whatever the orchestrator is running. Always dispatched in the FOREGROUND — the orchestrator is blocked on the brief anyway, so backgrounding it adds stall risk for zero parallelism.
- **auditor** [reasoning, inherit]: On demand only — dispatched after 2 failed attempts. Diagnoses root constraint, redesigns approach, re-briefs the team. Called to think, not to code. Rides the session model, same as planner. Same rule: FOREGROUND, not backgrounded.
- **reviewer** [smart]: Quality gate after Builders — reads the DIFF, checks logic/rules/conventions, patches small problems, spot-checks at most one targeted test file. NEVER re-runs full test suites or harness batteries (the builder's DoD numbers already cover that); flags anything bigger to the orchestrator.
- **builder-fast** [smart, sonnet]: Default implementation tier — scoped features, bug fixes, and small multi-file changes, not just a single tiny edit.
- **builder-smart** [reasoning, opus]: The exception, not a parallel tier — opus is for strategy, sonnet for attacks. Dispatch when a sonnet attempt failed, or when the implementation itself demands strategy-grade reasoning no brief can pre-decide (novel algorithms, subtle concurrency). Serialized by file.
- **builder-trivial** [fast, haiku]: Bulk mechanical work across 5+ sites (mass renames, bulk i18n/config, stub generation). Light per-site judgment is now acceptable; run many in parallel.
- **finder** [fast]: Codebase search — files, call chains, patterns. Read-only. Parallel-safe.
- **researcher** [fast]: External docs, API references, library behavior. Read-only. Parallel-safe.
- **tester** [fast]: Independent validation at ARC CLOSE only (or when a builder couldn't run its own proof) — runs the arc's combined DoD checks once. Not a per-card step: builders prove their own DoD. Read-only. Parallel-safe.
- **watcher** [fast, haiku]: Runs slow / long-running / noisy processes (servers, builds, test suites, deploys, log streams) and returns only a tight digest — a one-line verdict plus verbatim errors on failure. Context firewall: keeps high-volume output out of the orchestrator. One-shot — can smoke-boot and log-sample a server, but cannot hold one alive across dispatches. Cannot babysit OTHER dispatched subagents — `TaskOutput`/`TaskList` are scoped to the dispatching session, so a sibling watcher has no visibility into a task it didn't create. That polling loop stays with the orchestrator itself (rule 4c).

Rule of thumb: "Where is X in the code?" → finder. "How does library Y work?" → researcher.

**Pipeline**: [planner briefs — only if ambiguous/architectural/risky-core] → orchestrator dispatches finders/researchers (parallel, write to `findings.md`) → orchestrator dispatches builders (trivial/fast in parallel, smart serialized by file; each proves its own DoD) → reviewer diff-pass (risky arcs) → tester once at arc close → orchestrator closes on green numbers. `watcher` sits outside this line as an ad-hoc context firewall — the orchestrator dispatches it at any stage to run a server, build, or test suite without flooding its own context.

**Findings** (`.localdev/workflow/findings.md`): When Finders or Researchers discover something other agents need to know before acting, write it here. Builders read it before starting. Ephemeral — delete on session close. Difference from blockers: findings *inform*; blockers *halt until resolved*.

## Slash Commands

- `/agentic <task> [--tier=trivial|medium|full]` — explicit one-shot dispatch with tier control. *The main chat already auto-applies this pipeline under Orchestrator mode; use this command only to pin a specific tier or force-dispatch when the reflex rules would skip.*
- `/init-agentic` — scaffold `.localdev/workflow/` + `docs/KNOWN_ISSUES.md` in the current project
- `/handoff <task-name>` — write a cross-session handoff from current session context
- `/blocker <summary>` — append a decision blocker in canonical format and halt
- `/known-issue <summary>` — append to `docs/KNOWN_ISSUES.md`
- `/qq <question>` — quick side question answered by haiku in one fast turn (full conversation context, read-only tools); repeat `/qq` to continue the side thread. Session model untouched.

## Tier semantics

`/agentic <task>` routes by tier. Default is `medium`. Tier controls pipeline depth and therefore cost — `trivial` stays on fast models only.

| Tier | Pipeline | When to use |
|---|---|---|
| `trivial` | `builder-trivial` (or one `builder-fast`) → done. No planner. | Mass rename, bulk i18n/config entries, stub generation; single-line fix, typo, config tweak, doc edit |
| `medium` *(default)* | Orchestrator card → Finders/Researchers (parallel, if needed) → Builders (prove own DoD). **No Planner, Reviewer, or Tester.** Planner joins only if the task is ambiguous/architectural. | Small feature, scoped refactor, bug fix with tests |
| `full` | Planner brief → Finders → Builders (prove own DoD) → Reviewer diff-pass → Tester once at arc close → orchestrator closes on green numbers | Cross-cutting change, core physics/engine, schema/migration, security-adjacent, high-stakes refactor |

Rules:
- Never run `full` as a default — the user opts in for genuinely risky work.
- `trivial` must NOT fall through to `medium` as a safety net; skipping Reviewer is the point.
- Within `trivial`: use `builder-trivial` for pure mechanical/bulk work (mass renames, bulk i18n/config entries, stub generation); fall back to `builder-fast` when the single task still needs light judgment.
- Ambiguous task → dispatch Planner at inferred tier, but instruct it to ask a clarifying question BEFORE dispatching subordinates.

## Canonical entry formats

Blockers and handoffs use fixed formats so hooks and slash commands can parse them reliably.

### `.localdev/workflow/todo.md`

`todo.md` is a lightweight status board — it holds only OPEN cards, nothing else. Card format:

```markdown
# Todo

## [doing] <task title>
- Assignee: builder-fast
- Attempts: 1/2
- DoD: <verifiable done criteria>
- Deps: <other task title, or "none">
```

Status is one of `[todo]`, `[doing]`, `[blocked]`. A `[blocked]` card pairs with a full entry in `blockers.md` — `blockers.md` holds the question/context, the card just holds board state. `Attempts` ties into the 2-strike rule: increment per failed approach; at `2/2`, STOP and dispatch an Auditor. When a task completes, its card is REMOVED from `todo.md` and an entry is APPENDED to `done.md` — see below.

Legacy ledgers: a `todo.md` in the old checkbox-brief format (no `[status]` tags) is migrated on first touch — open items become `[todo]`/`[doing]` cards, completed items get dated entries in `done.md`, then work proceeds on the new format. No separate migration tooling; the orchestrator does it inline.

### `.localdev/workflow/blockers.md`

```
# Active Blockers

## YYYY-MM-DD HH:MM — <summary>
- Context: <current task + what you were doing>
- Blocker: <what you cannot resolve from code, docs, or git history>
- What I need: <the decision you need from the user>
- Files involved: <path list>
```

The H2 header MUST start with `## ` followed by a 4-digit year. The SessionStart hook uses `grep -qE '^## [0-9]{4}-'` to detect active blockers; mismatched heading depth = silent false negative.

### `.localdev/workflow/handoffs/<task-name>.md`

```
# <task>

## Status
<what was done>

## Next
- [ ] <next step>
- [ ] <next step>

## Open questions
<list or "None">

## Files touched
- <path>
```

On task completion, absorb this content into the corresponding `done.md` entry and delete this file — a handoff should never outlive its task.

### `.localdev/workflow/findings.md`

Flat append log — no structural requirements. Ephemeral; delete on session close.

### `.localdev/workflow/done.md`

Append-only completion log. Entry format:

```markdown
# Done

## 2026-07-02 23:40 — <task title>
- Summary: <1–3 lines: what shipped and how it was verified>
- Links: PR #12, JIRA ABC-345, commit 774b73a  <!-- whatever applies; "none" ok -->
- Files: <key paths touched>
- Attempts: 1
```

The header format `## YYYY-MM-DD HH:MM — <title>` deliberately matches `blockers.md`'s parseable convention (`^## [0-9]{4}-`). Rules: append-only, chronological, never loaded into session context wholesale (it grows unbounded by design), never deleted at session close (unlike `findings.md`). It can be indexed into context-mode's FTS knowledge base for historical search.

## Pre-granted permissions

Framework paths are pre-allowed in `~/.claude/settings.json` (global scope) so sessions don't prompt when agents write to them:

```
Write(.localdev/workflow/**)
Edit(.localdev/workflow/**)
Write(.localdev/workflow/handoffs/**)
Edit(.localdev/workflow/handoffs/**)
Write(docs/KNOWN_ISSUES.md)
Edit(docs/KNOWN_ISSUES.md)
```

One-time setup, covers all projects. Scope matches framework footprint — no broader write access granted.

### Per-project builder permissions (required for background dispatch)

The globs above cover only the framework's OWN files. Builders edit real source files and run real commands — with no further grants, every such tool call needs interactive approval, and **a backgrounded subagent's permission prompt is invisible**: the agent pauses silently until the user happens to focus it in the UI. This is the dominant cause of multi-minute pipeline stalls, and no amount of polling fixes it (rule 4c).

Before running the multi-agent pipeline in a project, pre-approve what builders need — per project, in `.claude/settings.local.json` (auto-gitignored):

```json
{
  "permissions": {
    "defaultMode": "acceptEdits",
    "allow": [
      "Bash(npm test:*)",
      "Bash(npm run build:*)"
    ]
  }
}
```

- `defaultMode: acceptEdits` — Edit/Write in the project tree no longer prompt (session-wide, subagents included).
- `allow` — the Bash commands builders actually run in THIS project (test runner, build, linter). Grow the list from real usage; Claude Code's `/fewer-permission-prompts` can generate it from transcripts.

`/init-agentic` offers to scaffold this. If a project deliberately opts out, do NOT background builders there — run them foreground so prompts surface immediately.

## SessionStart hook

On every session start, the hook (installed in `~/.claude/settings.json`) scans the CWD for `.localdev/workflow/` and prints:
- Any `.md` files in `handoffs/` (resume context)
- A warning if `blockers.md` contains unresolved entries
- Open `[doing]`/`[blocked]` cards in `todo.md` (in-flight or stuck work; `[todo]` backlog cards are not surfaced)

Silent no-op if `.localdev/workflow/` does not exist in the project.

## File Layout

```
project-root/
├── .localdev/                      # add to .gitignore (not auto-ignored)
│   └── workflow/
│       ├── todo.md                 # active board — open cards only
│       ├── done.md                 # append-only completion log (date, summary, links)
│       ├── blockers.md             # unresolved ambiguity (halts work)
│       ├── findings.md             # ephemeral intra-session discoveries
│       └── handoffs/
│           └── <task-name>.md      # cross-session continuation
└── docs/
    └── KNOWN_ISSUES.md             # committed — permanent project knowledge
```

## When to Use What

| Situation | Action |
|---|---|
| Closing CC, will continue tomorrow | `/handoff <name>` |
| Closing CC after multi-agent session | Delete `findings.md` |
| Agent hit ambiguity it cannot resolve | `/blocker <summary>` |
| Found a platform limitation that'll bite again | `/known-issue <summary>` |
| Planning a non-trivial task | Add done criteria to each item |
| Task completed | Move card from `todo.md` to `done.md` (timestamp, summary, PR/Jira links) |
| Task done but handoff file still exists | Absorb into done.md entry, delete the handoff |
| Need history of past work | Search `done.md` (context-mode FTS) — don't load it whole |
| Request has 2+ interpretations | Clarify first, don't start |
| Starting an ambiguous / architectural / risky-core task | Dispatch `planner` subagent (foreground) |
| Starting a well-scoped task (shape already clear) | Write the todo.md card yourself, dispatch builders directly — no planner round |
| Need to find files or trace patterns | Dispatch `finder` (parallel) |
| Need library docs or API refs | Dispatch `researcher` |
| Dispatching subagents | Foreground for a single critical-path agent; background only when 2+ run concurrently (then poll per rule 4c) |
| Uncertain about API/command/lib behavior | Verify via context7/web before brief |
| Same edit across 5+ files/entries (one transform, N sites) | `builder-trivial` (parallel) |
| Scoped feature, small multi-file change, or single scoped edit | `builder-fast` (parallel where non-overlapping) — default implementation tier |
| Complex logic or core code | `builder-fast` with a sharper, decomposed brief — `builder-smart` (serialized by file) when sonnet failed or the code itself demands strategy-grade reasoning |
| Risky arc needs a quality gate | `reviewer` (smart) — diff-pass only, no suite re-runs |
| Verifying done criteria | Builder proves its own DoD; `tester` (fast) once at arc close only |
| Concurrent agents on one working tree | NO git-state mutation by anyone (stash/checkout/reset) — sandbox copies or config toggles instead |
| Running a server / slow build / long noisy process | `watcher` (haiku) — returns a digest, keeps output out of context |
| Background subagent stalled, no progress for minutes | FIRST suspect a pending permission prompt — tell the user to focus the task and approve, then fix the project allowlist. Only after that: poll `TaskOutput` every ~30s and `SendMessage`-ping if stuck (rule 4c) — cannot delegate to `watcher`, it has no visibility into a task it didn't dispatch |
| Runtime verification blocked (won't launch, env missing) | Mark **UNVERIFIED** + state the blocker — never imply success |
| Target is user-side hardware / device / auth | Give user exact commands, interpret their pasted output — don't probe locally |
| Problem survived 2 failed attempts | Dispatch `auditor` to re-diagnose |
| Simple bug fix, single session | None of this — just fix it |
