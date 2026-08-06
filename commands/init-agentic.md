---
description: Scaffold the Agentic Workflow Framework files for the current project (.localdev/workflow/ + docs/KNOWN_ISSUES.md)
---

Set up the Agentic Workflow Framework scaffolding in the CURRENT working directory.

# Steps

1. **Check state first** — don't overwrite existing content. For each path:
   - If it exists and is non-empty, leave it alone and report "already present".
   - If it doesn't exist, create it with the template.

2. **Create directory structure**:
   - `.localdev/workflow/handoffs/` (directory)
   - `.localdev/workflow/todo.md` — starter with `# Todo` heading, `## Tasks` section, and a comment explaining the DoD format.
   - `.localdev/workflow/done.md` — starter with `# Done` heading and a comment showing the entry format (`## YYYY-MM-DD HH:MM — <title>` with Summary/Links/Files/Attempts).
   - `.localdev/workflow/blockers.md` — starter with `# Active Blockers` heading and a comment explaining the entry format.
   - `.localdev/workflow/findings.md` — starter with `# Findings` heading and a note that the file is ephemeral.
   - `docs/KNOWN_ISSUES.md` — starter with `# Known Issues` heading and an entry-format comment.

3. **Gitignore hygiene** — if the current directory is a git repo:
   - Run `git rev-parse --is-inside-work-tree` to confirm.
   - Check if `.gitignore` already excludes `.localdev/` or `.localdev`. If not, append `.localdev/` on its own line (it is NOT auto-ignored, unlike the old `.claude/` convention).
   - Confirm `docs/KNOWN_ISSUES.md` is NOT gitignored (it should be committed).

4. **Builder permissions (prevents silent background stalls)** — background subagents that hit an unapproved Edit/Write/Bash pause invisibly until the user focuses them in the UI; pre-approving builder tools per project is what makes background dispatch viable (see AGENTIC.md § Pre-granted permissions).
   - Check `.claude/settings.local.json` in the project root. If it already sets `permissions.defaultMode`, leave it alone and report "already configured".
   - Otherwise ASK the user: "Pre-approve builder edits in this project (`defaultMode: acceptEdits` in `.claude/settings.local.json`, auto-gitignored)? Without it, backgrounded builders stall silently on permission prompts."
   - If yes: create or merge (preserve existing keys) `.claude/settings.local.json` with:
     ```json
     { "permissions": { "defaultMode": "acceptEdits", "allow": [] } }
     ```
     Then look at the project's test/build entry points (e.g. `package.json` scripts, `Makefile`) and offer matching `Bash(...)` allow entries — e.g. `Bash(npm test:*)`, `Bash(npm run build:*)`. Only add what the user confirms.
   - If no: note in the report that builders in this project must be dispatched FOREGROUND (prompts must surface immediately).

5. **Test conventions (feeds the targeted-tests rule)** — agents must never guess how this project runs tests:
   - If the project CLAUDE.md already has a `## Testing` section, leave it alone and report "already documented".
   - Otherwise detect the runner from `package.json` scripts, `Makefile`, `pyproject.toml`, `Cargo.toml`, or CI config, and offer to append a `## Testing` section to the project CLAUDE.md documenting: the runner, how to run a single file/pattern (e.g. `yarn jest <path>`, `pytest <path> -k <pattern>`), and workspace/package scoping if it's a monorepo. Only write what the user confirms.
   - If no test setup is detectable, note that in the report — DoDs in this project cannot include test scopes until one exists.

6. **Report** — print a structured summary: created paths, skipped paths (already present), gitignore status, permission setup outcome, test-conventions outcome.

Do NOT commit. Do NOT run any other setup commands.
