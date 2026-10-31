# Evidence and Action Records

Use one manifest for a delivery that spans scenarios, repositories, or sessions.
Keep the original requirements in a separate JSON file.
Use the manifest to link reported results to the exact source and conditions.
The checker reads local files and Git state. It does not run recorded commands.

## Run the checker

```bash
python3 -I <skill>/scripts/evidence.py check <manifest.json> --json
```

The checker writes one JSON object to stdout. It does not write files.

| Exit | Status | Meaning |
| --- | --- | --- |
| 0 | `PASS` | The declared coverage and measured identity checks pass. |
| 1 | `FAIL` | The schema, identity, result, or approval record has a contradiction. |
| 2 | `UNVERIFIED` | A required scenario, log, artifact, or inspection is unavailable. |

`FAIL` takes precedence over `UNVERIFIED`. Invalid CLI arguments use exit 2.
A missing required row cannot produce `PASS`. An empty original scenario list is invalid.
Unknown fields, duplicate IDs, duplicate JSON keys, and unsupported statuses fail.

The report separates these fields:

- `measured`: current repository identity, checker runtime, selected environment variables, and file hashes.
- `reported`: scenario statuses, action permissions, decisions, conflicts, and owners.
- `failures`: contradictions that produce `FAIL`.
- `unverified`: missing evidence or unresolved conflicts.
- `limits`: the boundary of the check.

`PASS` does not prove that a command ran or that a log describes a real test.
The checker cannot judge arbitrary logs, approve security, or grant permission.
A report of authorization is not authorization itself.
Check the cited user message or policy before each action.

## Version 1 schema

[evidence.schema.json](evidence.schema.json) defines the closed JSON Schema.
The CLI checks its supported schema rules with the Python standard library.
Both documents require the integer `schema_version: 1`.
Use `$defs.manifest` for a manifest and `$defs.requirements` for original requirements.
All object fields are required unless the schema states otherwise.
No object accepts unknown fields. Environment maps accept named variables.

[The example](evidence.example.json) shows both documents in one teaching wrapper.
The wrapper is not a manifest. Its placeholder hashes do not represent valid evidence.
The executable tests create complete documents in temporary Git repositories.

### Original requirements

Record the following fields before collecting evidence:

- `delivery`: a stable delivery ID.
- `source`: the request or decision that defines the delivery.
- `source_paths`: literal repository-relative files or directories relevant to the checks.
- `scenarios`: the nonempty original scenario matrix.
- `permissions`: one entry for each independent action.
- `owners`: named owners with scope and source.
- `decisions`: existing decisions that the delivery must preserve.
- `conflicts`: existing conflicts with their sources and owners.

Each scenario records these fields:

| Field | Meaning |
| --- | --- |
| `id` | Stable ID from the original request. |
| `platform` | Required platform, such as browser or macOS. |
| `claim` | The exact observable result that the scenario must support. |
| `owner` | An ID from `owners`. |
| `command` | Exact `argv` array and absolute `cwd`. |
| `runtime` | Exact product runtime and version, as reported by the runner. |
| `environment` | Relevant environment variable names and exact values. Use null for an absent variable. |
| `provenance` | `source`, `unit`, `contract`, `synthetic`, `application`, or `installed`. |
| `artifact_required` | Whether this claim needs an artifact file. |

Include successful reset and canceled reset as different scenarios when both are required.
Do not replace a browser scenario with a Desktop result.
Use explicit source paths for ignored inputs that affect the result.
Include dependency locks, runner configuration, generated inputs, and direct dependencies when relevant.
The checker cannot infer which files or environment variables matter.
Do not place secrets in the environment map.

Keep the requirements file outside the measured source paths.
Preserve its initial hash in the task card or another trusted record.
The manifest stores its absolute path and SHA-256 in `requirements`.
The checker detects a changed file against that hash.
It cannot detect someone replacing both the requirements and their trusted hash.
This is an integrity check, not a signature or a permission system.

### Independent action permissions

Record all seven actions: `implement`, `commit`, `push`, `pr-state`, `comment`, `resolve-thread`, and `merge`.
Each entry has `action`, `status`, `source`, and `scope`.
Statuses are `authorized`, `prohibited`, `not-requested`, or `pending`.
A source has `kind` and `reference`.
Source kinds are `user`, `accepted-agent-proposal`, `policy`, `not-requested`, or `reported`.
An authorized entry requires a user, accepted proposal, or policy source.
The checker checks that record, not the truth of its source.

Copy the original permission entries into the manifest without changes.
Do not turn `not-requested` into a user prohibition.
A closed PR can coexist with separately authorized commit and push actions.
A passing evidence report does not authorize either action.
For a new user instruction, preserve the previous record before creating revised requirements.
Cite the new instruction and the affected scope.
Do not rewrite the history of who proposed a restriction.

### Repository and execution identity

`repository` contains these fields:

- `realpath`: absolute Git worktree root after symlink resolution.
- `branch`: current short branch name, or `DETACHED`.
- `base`: full base commit ID, not a branch name.
- `commit`: full current commit ID.
- `index_sha256`: SHA-256 of relevant staged entries.
- `inputs`: sorted relevant file paths, SHA-256 values, and modes.
- `dirty`: sorted relevant dirty paths, porcelain status, SHA-256 values, and modes.

A missing file has null `sha256` and mode `missing`.
Regular file modes are `file` or `executable`.
The schema reserves `symlink`, but this version reports source symlinks and submodules as `UNVERIFIED`.
It does not follow them as source inputs.
The checker includes tracked files and nonignored untracked files under declared directories.
It also includes explicitly named ignored files.

The staged digest covers the bytes from this fixed, read-only Git command:

```bash
git ls-files --stage -z -- ':(literal)<source-path>'
```

Include one literal path argument for each declared path, in its declared order.
The Python helper `repository_identity(root, base, source_paths)` measures the complete object.
The helper does not run scenario commands.
`runtime_identity()` measures Python version, executable realpath, operating system, and machine architecture.
A producer can import these helpers by absolute file path with `importlib.util` under `python3 -I`.

An identity hash is SHA-256 of UTF-8 JSON with these Python encoding options:

```python
json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode()
```

Each evidence record contains these fields:

- `repository_sha256`: the identity hash of the complete recorded `repository` object.
- `checker_runtime`: the exact recorded `runtime_identity()` object.
- `command`, `runtime`, `environment`, and `provenance`: exact copies of the anchored scenario fields.
- `result`: `PASS`, `FAIL`, or `UNVERIFIED`.
- `exit_code`: the reported integer process result, or null when unavailable.
- `log`: an existing absolute file path and its SHA-256.
- `artifact`: null or an existing file with `path`, `sha256`, and `source_identity_sha256`.

`PASS` requires reported exit code zero and an unchanged existing log.
An installed claim always requires an artifact.
An artifact source identity must equal `repository_sha256`.
The checker measures the artifact bytes but cannot establish how someone built them.
A synthetic result cannot support an application or installed scenario.
The product runtime string remains reported. The checker does not launch a product to inspect its version.
For persistent servers, record the actual server identity in the runner log and the relevant environment fields.
A reviewer must check that the server uses the recorded source.

### Matrix, decisions, and conflicts

`matrix` retains one row per original scenario ID, including missing or excluded work.
Each row has `id`, `status`, `reason`, `decision`, and `evidence`.
Statuses are `PASS`, `FAIL`, `UNVERIFIED`, and `EXCLUDED`.
Use null evidence when a required run is unavailable.
List every `UNVERIFIED` row in the completion report.

A scope reduction keeps the original scenario and its row.
Use `EXCLUDED`, a reason, null evidence, and a decision ID.
The decision must have kind `scope-reduction`, status `approved`, and the scenario ID in `scenarios`.
Its source must cite a user instruction or an accepted agent proposal.
The report preserves the exclusion. It does not claim the original full scope passed.

Decisions record `id`, `kind`, `status`, `source`, `owner`, `scenarios`, and `summary`.
Kinds are `decision`, `scope-reduction`, or `conflict-resolution`.
Statuses are `approved`, `pending`, or `rejected`.
Conflicts record `id`, at least two `sources`, `owner`, `status`, and `decision`.
Original decisions cannot disappear or change in the manifest.
Original conflicts keep their sources and owners. An open conflict can gain an explicit resolution.
An open conflict produces `UNVERIFIED`.
A resolved conflict requires an approved decision of kind `conflict-resolution`.
Record the current behavior and conflicting source before asking for a new decision.

## Batch checks and reuse

1. Integrate the ready batch before running its checks.
2. Capture the original scenarios and exact production commands.
3. Measure source identity and conditions before the run.
4. Run the commands through the authorized project runner, not through this checker.
5. Preserve each command's result and existing log.
6. Measure source identity again after the run.
7. Reject the evidence if relevant source or conditions changed during the run.
8. Run this checker against the completed manifest.
9. Reuse a result only when its full identity still matches.

A commit match alone is insufficient. Dirty content, staged content, commands, runtime, environment, provenance, and logs must also match.
A screenshot failure does not invalidate a separate, unchanged persistence check.
Repeat only the missing claim when the other identity checks still pass.
Do not treat an installation failure as a successful test or a measured product failure.
Report the affected scenario as `UNVERIFIED` with the reason.

## Stack checker integration

For each node, require exact equality between its worktree and `repository.realpath`.
Require exact equality between its full head and `repository.commit`.
Require checker `PASS` for that node's manifest.
For every node `required_commands` entry, match the complete anchored scenario `command` object.
Require its matrix row to report `PASS`, not `EXCLUDED`.
Require the row's source identity to equal the complete repository identity hash.
Require exact runtime and environment agreement with the node's persistent environment contract.
For packaged checks, require an artifact and its source identity.
Never search a log or free-text field for a SHA.
The stack checker must not label a reported command result as an independently measured execution.
