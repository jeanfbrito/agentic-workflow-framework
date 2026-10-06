---
name: "personal-engineering-rules"
description: "Apply Jean's conventions. Use when porting reference behavior, fixing a bug, writing or keeping a test, shaping a module boundary, evaluating review feedback, or writing engineering reports."
---

# Personal Engineering Rules

Apply the relevant convention while preserving the user's chosen scope.

## Reference Behavior and Fixes

When porting behavior, inspect the relevant reference implementation and enough
of its input/output pipeline to preserve coordinate transforms, units, ordering,
and edge cases. Expand the read when a dependency changes the result; an entire
reference repository is not a prerequisite to a scoped port.

Prefer a root-cause fix. When a constraint calls for a workaround, make its
limitation explicit and keep it within the requested outcome. Resolve ordinary
implementation choices from evidence; ask only for a material missing decision.

## Bug Fixes

Reproduce on the surface the user sees before fixing. If it will not reproduce,
tighten conditions or instrument until it fires. Every shipped line traces to
runtime evidence: a change that "might help" is a hypothesis, and code a refuted
hypothesis motivated is reverted. When something fails after a restart, suspect
persisted state (config, caches, stored window or session state) before code.
Order commits so the failing repro or test lands before the fix.

## Tests

Before keeping a test, ask whether it would still pass if every function it
imports returned `undefined`. If yes, it cannot fail for a defect: rewrite the
assertion or delete the test. These shapes fail this check: no or weak
assertions (`toBeDefined`, `toBeTruthy`, `not.toThrow`), and mock-call-only
assertions. Others are an expected value computed by the code under test, a restated
constant or config default, and a fixture asserting on itself. Call the subject
with one concrete input and assert the literal output or the observable effect.

## Module Boundaries

Assume the next contributor is an agent that sees only the files it opened,
copies the nearest example, and takes the shortest path that compiles. Reject a
shape with two ways to do one task, or internals importable from outside the
module. Reject a list that must be hand-synced with another, or state written by more
than one owner. Keep one way, make internals unreachable, derive the second
list, and give each piece of state one owner.

## Review Feedback

Treat bot and agent comments as hypotheses to check against the code and request.
Before changing an invariant, schema, or contract, inspect the affected callers
and consumers. Do not apply a suggestion solely because a reviewer made it.

Fix every valid finding on the branch before merging, including a pre-existing
issue the change makes likelier to surface, with bot threads resolved and the
PR body current. Deferring a finding to a follow-up is the user's call, asked
before the merge.

## Engineering Reports

Preserve technical truth in postmortems, PR descriptions, changelogs, and incident
reports. Describe the observed scope and validation gaps. Use terms such as
"regression" or "failed in production" when evidence supports them; do not soften
an established failure or imply a failure that was not observed.

Before reporting a measured number (speedup, regression, CI timing), vet it with
the `benchmark-checklist` skill. Name what limits it. Rule out errors,
skipped work, untuned sides, and noise.

Distinguish source inspection, focused tests, and live behavior. Report a blocked
check and its practical limit without implying that untested behavior passed.

## Authorization

Do not commit, push, or open a PR without a user request authorizing that action.
Preserve authorization already given in the session. Change durable memory only
when explicitly requested; an observed lesson is not permission to save it.
