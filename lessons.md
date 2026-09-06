# Lessons

## Arc "closed" without deploying to the live environment (Cost: 1 user correction)
**What happened**: The 2026-08-09 hook-suite arc was declared complete after tester validation — but every DoD ran in temp HOMEs (`HOME=$(mktemp -d)`), so the real `~/.claude` still had the old inline scanner and none of the new hooks. The user had to ask "all we have running already?".
**Root cause**: the cards' DoDs deliberately used temp HOMEs (correct for testing) but no card — and no arc-close step — owned "run install.sh against the real HOME".
**What solved it**: `bash install.sh --yes` for real; its built-in verify passed.
**Rule**: any arc in this repo touching install.sh/hooks/agents ends with a live `bash install.sh` + `verify.sh` run as an explicit arc-close step, and the report must state that new/changed hooks only load at the NEXT session start (current session keeps the old config).

## Hook stdin convention: HOOK_STDIN_JSON env var, never sys.stdin in a heredoc (Cost: latent bug shipped in card 1, caught in card 2)
**What happened**: `hooks/session-scan.sh` and `pre-compact.sh` read hook JSON with `sys.stdin.read()` inside a `python3 <<'PYEOF'` heredoc — the heredoc is the interpreter's stdin, so the piped hook payload was silently never seen (`source`/`trigger` always empty). Card 1's fixtures passed because none asserted on stdin-derived fields.
**Root cause**: heredoc-as-script consumes stdin; failure is silent (empty string, no error).
**What solved it**: capture stdin in bash first — `HOOK_STDIN_JSON="$(cat)"`, export, read `os.environ` in the python block.
**Rule**: every hook in this repo that embeds python and needs the hook payload MUST use the `HOOK_STDIN_JSON` pattern (see session-scan.sh); fixture tests MUST assert at least one stdin-derived field (e.g. `source`/`trigger`), not just file-derived output.

## Discovery: stop-ledger-audit.sh excludes the paths test fixtures naturally land in
**Context**: card 3's positive fixture didn't fire check 1 — it lived under the session scratchpad (`/private/tmp/claude-*/...`), which the audit script correctly excludes from the file-write count (alongside `.localdev/`).
**Insight**: fixtures for the audit hook must live in a neutral `mktemp -d` (like verify.sh Check 6c does), never the scratchpad.
**Implication**: when testing any exclusion logic in this repo's hooks, check the exclusion list against where your fixture lives first.

## Discovery: install.sh conventions the hook suite established (2026-08-09 arc)
**Context**: four cards touched install.sh/uninstall.sh/verify.sh serially.
**Insight**: idempotency marker = the hook script's own filename in the settings.json command string (strip-by-marker on upgrade also strips the pre-v4 'agentic: armed' inline blob); CORE_COUNT counts AGENTIC.md + installed scripts; every hook gets a verify.sh fixture check (6b/6c/6d pattern) that executes the real script, not a reimplementation.
**Implication**: new hooks/scripts follow the same triad (install_file + marker wiring + verify fixture check) or verify.sh drifts from reality. Marketplace/plugin path cannot ship non-hook utilities to `~/.claude/hooks/` — ledger-append.sh is shell-installer-only (open decision whether plugin users need a variant).

## Lesson: haiku finders hang when allowed to script over large trees (2026-09-06, coi-terrain)
**Context**: three `finder` dispatches against a repo with a 100k-symbol decompiled C# tree went silent for 30+ min each; killed mid "let me create a processing script". A same-question redispatch with numbered steps, named files and a 12-call cap returned in 80–160 s.
**Root cause**: finder.md made `ctx_execute`/`ctx_batch_execute` MANDATORY for large outputs, and put no budget on the scout. Haiku obeyed: unbounded `grep -r` over the tree inside a sandbox script → MCP idle timeout (1800 s) → nothing returned. `ctx_batch_execute` from the orchestrator over the same tree also timed out twice.
**Fix**: removed `ctx_execute`/`ctx_batch_execute` from the finder toolset; added hard budget (12 calls / 10 min → `PARTIAL` reply), "never write scripts", "size a directory before any recursive grep (>200 files → named files only)".
**Rule for orchestrators**: finder briefs name the files and number the steps; if a finder is silent past ~5 min, kill and redispatch narrower — do not wait 30.
