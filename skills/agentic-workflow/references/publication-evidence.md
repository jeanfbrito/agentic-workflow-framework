# Evidence for final publication heads

Use `scripts/publication.py` beside the existing evidence checker.
This opt-in contract leaves the version 1 evidence schema unchanged.
It checks local final heads and declared external inputs. It never executes recorded commands or contacts a remote.

## Requirements

Create a separate requirements file before the verification run:

```json
{
  "version": 1,
  "node": {
    "root": "/absolute/worktree",
    "branch": "refs/heads/feature",
    "base": "FULL_BASE_COMMIT",
    "head": "FULL_FINAL_COMMIT",
    "source_paths": ["path/to/tested/scope"]
  },
  "dependencies": [
    {
      "id": "framework-runner",
      "root": "/absolute/framework/worktree",
      "base": "FULL_DEPENDENCY_BASE_COMMIT",
      "source_paths": ["skills/agentic-workflow"]
    }
  ]
}
```

Choose source paths that cover the claim. For stack publication, include all tracked inputs as required by the stack checker.
Dependencies use Git repository identity, including dirty bytes and staged entries.
Include the checker, schema, runners, configuration, and libraries that the command actually uses.
An empty dependency list explicitly declares that no external repository input is relevant.
The checker cannot discover omitted dependencies or establish whether this declaration is complete.
Non-Git dependencies still need artifact or environment evidence. This helper does not inspect package registries.

## Capture, run, and seal

1. Create the final commit under the user's commit authorization.
2. Capture identity before the test run:

```bash
python3 -I <skill>/scripts/publication.py capture requirements.json > before.json
shasum -a 256 before.json
```

3. Preserve that snapshot hash in the task card before running the checks.
4. Execute the exact authorized test command through the project runner.
5. Create a version 1 evidence manifest with the same node identity and source paths.
6. Seal the result with the preserved hash:

```bash
python3 -I <skill>/scripts/publication.py seal before.json evidence.json \
  --snapshot-sha256 <PRESERVED_HASH> > publication.json
python3 -I <skill>/scripts/publication.py check publication.json
```

The scripts print JSON. The shell redirects output to the specified local files.
Exit 0 means PASS, exit 1 means FAIL, and exit 2 means UNVERIFIED.
Do not treat a failed seal's output as a publication record.
Keep all records and logs outside measured source paths.
Each node needs its own snapshot, evidence manifest, and publication record.

A changed head, dependency, snapshot, or evidence file invalidates the binding.
A new commit requires evidence tied to that commit, not a rewritten identity on an older result.
If tests already ran without a snapshot, report that gap. Do not invent a pre-run capture.
Run only the affected checks when earlier evidence remains valid under the existing identity rules.

## Integration and limits

Set `EVIDENCE_FRAMEWORK_ROOT` explicitly for the split-pr-stack integration test.
Its value is the framework skill directory under test, not the repository root.
Record that environment variable in the scenario. Record the selected framework as a dependency.
The integration test fails when the variable is absent. It does not silently select another clone or skip the check.
A stack node can set `publication` to its absolute publication record path.
Existing nodes without that field retain the old behavior. Do not describe them as dependency-bound publication checks.

This record is an integrity check, not a signature.
Someone who rewrites the snapshot and trusted hash can change its history.
The checker cannot prove that a log came from the recorded run.
After an authorized push, compare the remote ref with the checked head separately.
A local PASS does not prove remote delivery, CI success, or permission to publish.
