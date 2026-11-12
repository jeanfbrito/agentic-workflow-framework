# GitNexus

How to use the GitNexus code graph, keep its index healthy, and keep it out
of a shared repository. GitNexus is a personal tool. A repository that other
people use must not depend on it. Its `AGENTS.md`, `CLAUDE.md`, skills and
hooks must work without it.

## Keep GitNexus out of a shared repository

`gitnexus analyze` writes into the repository unless you stop it. It appends a
GitNexus block to `AGENTS.md` and `CLAUDE.md`, creates `CLAUDE.md` when the
repository has none, and writes generated skills to `.claude/skills/gitnexus/`.
Set up each indexed repository so that nothing of this gets committed:

1. Create `.gitnexusrc` in the main checkout with `{ "skipAgentsMd": true }`.
2. Add these lines to `.git/info/exclude` (local, never committed):

   ```text
   .gitnexus/
   .gitnexusrc
   .claude/skills/gitnexus/
   ```

3. Always analyze with `--index-only`. It skips every generated file.
4. After `analyze`, run `git status`. A modified `AGENTS.md` or `CLAUDE.md`,
   or a new `CLAUDE.md`, means a GitNexus version ignored `.gitnexusrc`.
   Revert the change with `git checkout --` and delete a new `CLAUDE.md`.

The global skills in `~/.claude/skills/gitnexus-*` explain each tool, so a
repository needs no copy. The `gitnexus-scope.cjs` hook in `~/.claude/hooks/`
fills the worktree arguments (see below).

## Rules

- Run `impact({target: "<symbol>", direction: "upstream"})` before you edit a
  function, class or method. Report the direct callers, the affected flows and
  the risk level.
- Warn the user when `impact` returns HIGH or CRITICAL risk, before you edit.
- Treat `risk: UNKNOWN` as unresolved, not as low. The index cannot resolve
  some callers: a property access on a plain object, a string-keyed channel
  (IPC, events), dynamic dispatch, and calls across a language or process
  boundary. Check with a text search before you change or remove the symbol.
- Run `detect_changes()` before you commit, to check that the change touches
  only the expected symbols and flows. A result with `partial: true` or
  `truncated: true` is not a clean check. Run it again.
- To explore unfamiliar code, use `query({query: "<concept>"})`. For one
  symbol's callers, callees and flows, use `context({name: "<symbol>"})`.
- Rename a symbol with `rename`, not with find-and-replace.
- A missing or stale symbol is unknown impact. Use a bounded source lookup to
  close the gap.
- Do not name GitNexus, or paste its output, in a PR description, commit body
  or issue of a shared repository.

## Reindex

- Reindex only from the main checkout, at a quiet point:
  `node .gitnexus/run.cjs analyze --index-only`. No `.gitnexus/run.cjs` yet?
  Run `npx gitnexus analyze --index-only` (if npm 11 crashes, run
  `npm i -g gitnexus`, see GitNexus #1939).
- Do not run `analyze` inside a linked worktree. It registers a second index
  under the same name. Lookups by that name then fail with "Multiple
  registered repos match", and the extra index goes stale. To remove it, run
  `gitnexus clean --force` in that worktree.
- Keep the quiet point. A background `analyze` was suspected of dropping
  freshly staged files and of restarting a file-watching dev server
  (`yarn start`). Upstream could not reproduce it (GitNexus #2906).
- After `gitnexus setup`, run `claude mcp get gitnexus`. Setup can write a
  stale binary path into the MCP configuration.

## Linked worktrees

The MCP server serves the index of the main checkout, and it diffs the
checkout that the session was started from. This stays true when you edit
files in a linked worktree.

- Pass `repo: "<indexed name>"` to every repo-scoped tool. Do not pass it to
  `list_repos`, which takes only `limit` and `offset`. A session started
  inside a worktree can fail without it.
- Pass `worktree: "<absolute worktree path>"` to `detect_changes`. Without it,
  a session started in the main checkout diffs the main checkout and misses
  every change in the worktree.
- The `gitnexus-scope.cjs` PreToolUse hook fills a missing `repo` and, for
  `detect_changes` in a linked worktree, a missing `worktree`. It never
  replaces a value that the call already has.
- `query`, `context` and `impact` describe the main checkout at its indexed
  commit. `list_repos` shows that commit and how far it is behind. For a
  symbol that your branch adds or changes, read the source.
- `detect_changes` maps changed lines to symbols through that same index. A
  stale index can name the wrong symbol, so reindex the main checkout before
  a review that depends on exact symbols.
- `compare` runs `git diff <base_ref>` against the working tree. A stale local
  default branch, or a remote branch that moved past the branch point, adds
  changes that are not yours. Pass the merge base:
  `git fetch origin <base> && git merge-base origin/<base> HEAD`, then
  `detect_changes({scope: "compare", base_ref: "<merge-base sha>"})`.

## Resources

| Resource                                 | Use for                                  |
| ---------------------------------------- | ---------------------------------------- |
| `gitnexus://repo/<name>/context`         | Codebase overview, check index freshness |
| `gitnexus://repo/<name>/clusters`        | All functional areas                     |
| `gitnexus://repo/<name>/processes`       | All execution flows                      |
| `gitnexus://repo/<name>/process/{name}`  | Step-by-step execution trace             |
