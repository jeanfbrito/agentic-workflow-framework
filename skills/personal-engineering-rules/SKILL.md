---
name: "personal-engineering-rules"
description: "Apply Jean's conventions when porting reference behavior, evaluating review feedback, or writing engineering reports."
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

## Review Feedback

Treat bot and agent comments as hypotheses to check against the code and request.
Before changing an invariant, schema, or contract, inspect the affected callers
and consumers. Do not apply a suggestion solely because a reviewer made it.

## Engineering Reports

Preserve technical truth in postmortems, PR descriptions, changelogs, and incident
reports. Describe the observed scope and validation gaps. Use terms such as
"regression" or "failed in production" when evidence supports them; do not soften
an established failure or imply a failure that was not observed.

Distinguish source inspection, focused tests, and live behavior. Report a blocked
check and its practical limit without implying that untested behavior passed.

## Authorization

Do not commit, push, or open a PR without a user request authorizing that action.
Preserve authorization already given in the session. Change durable memory only
when explicitly requested; an observed lesson is not permission to save it.
