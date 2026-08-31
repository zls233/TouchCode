# TouchCode agent workflow

## Model routing

- Default executor: `gpt-5.6-luna` with `medium` reasoning. It reads the
  repository, searches documentation, runs commands, edits code, and runs
  tests.
- Escalate before implementation to `gpt-5.6-sol` with `xhigh` reasoning for a
  cross-module architecture decision, a difficult or repeated bug, a change
  with irreversible product or security consequences, or a decision where the
  Luna investigation cannot choose safely between viable approaches.
- Do not escalate routine implementation, a single-file bug, an error with a
  direct compiler/test diagnosis, or a command-only validation task.

## Sol task packet

Give Sol only a 1,000–3,000-token task packet. It must contain:

1. The desired outcome and acceptance checks.
2. The smallest relevant code excerpts and file paths.
3. Product, compatibility, safety, and existing-change constraints.
4. Observed behavior, exact failures, and approaches already attempted.
5. The specific decision or question Sol must resolve.

Do not send the complete repository, unrelated logs, or repeated project
background. Ask Sol for a structured recommendation: diagnosis, options and
trade-offs, chosen approach, implementation sequence, validation plan, and
remaining risks. Luna implements and independently validates that plan.

## Development loop

1. Inspect the branch, diff, and current baseline; preserve all user changes.
2. Let Luna complete one bounded, verifiable development slice.
3. Escalate through a task packet only when the routing criteria apply.
4. Run the smallest relevant checks, then broader checks when the slice crosses
   package or app boundaries.
5. Evaluate: acceptance result, regression risk, unverified paths, and the
   next highest-priority slice. Continue the next cycle without repeating work.

Never reset, overwrite, delete, push, publish, purchase, or call paid external
providers without explicit user approval.
