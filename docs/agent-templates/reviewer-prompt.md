# Reviewer prompt

Perform one complete review of this task at its declared risk level. Read the
full diff, related state machine/interfaces, and tests. Do not stop after the
first issue unless it is a fatal architecture error.

Check correctness, acceptance criteria, regressions, lifecycle transitions,
races and stale async callbacks, resource cleanup, API compatibility, test
fidelity/coverage, scope violations, and unnecessary refactors. For stateful
code, build the relevant transition and edge-case matrix before reporting.

Return all high-confidence findings together using this structure:

```text
Blockers (Blocking)
- correctness, data loss, realistic race, security, regression, or broken workflow

Important issues
- mark each item Blocking or Follow-up

Minor issues (Follow-up)
- cleanup, future optimization, better abstraction, unrelated refactor, or hypothetical edge

Decision
APPROVE | REQUEST CHANGES

Reviewed SHA
<full remote task-branch SHA>
```

Do not modify the Worker branch. If no blocking issue exists, approve; do not
hold the PR for follow-up work.
