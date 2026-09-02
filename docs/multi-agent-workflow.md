# Multi-Agent Git workflow

TouchCode uses one task, one worktree, one branch, and one Pull Request.
`AGENTS.md` is the authoritative rule set; this page is the practical
reference for a task lifecycle. The efficiency target is one investigation,
one complete task packet, one implementation pass, one self-review, one
independent review, and at most one consolidated fix pass.

## Lead start gate

Classify the task before creating a worktree:

| Level | Typical work | Required review |
| --- | --- | --- |
| 1 — Routine | Local bug, UI/copy/config, direct compiler fix, tests | Lightweight complete-diff review |
| 2 — Stateful / Cross-module | Async, networking, lifecycle, persistence, multi-module API | Full state/lifecycle/race review |
| 3 — Architecture / Security | Crypto, trust, protocol architecture, irreversible change | Minimal Sol decision, architecture freeze, security review |

Perform one batched investigation: Git baseline, approved plan, relevant
implementation/interfaces/tests/config. Create the task packet from
[`agent-templates/task-packet.md`](agent-templates/task-packet.md), including
invariants and all validation tiers. After Worker start, scope is frozen.

## Worker quick start

From the primary `main` checkout, create an isolated task checkout:

```bash
./script/create-task-worktree.sh improve-bridge-logging
cd ../TouchCode-worktrees/improve-bridge-logging
```

The script fetches `origin/main`, creates `task/improve-bridge-logging`, and
attaches that branch to the new worktree. Make all changes there. Do not start
implementation in the primary checkout.

During implementation, run targeted checks. Before review, run targeted and
affected-package checks. Reserve full repository, Xcode, and integration gates
for pre-merge when the scope requires them. Before delivery, use
[`agent-templates/worker-self-review.md`](agent-templates/worker-self-review.md),
commit atomically, and inspect:

```bash
git diff --check
git diff origin/main...HEAD
git push -u origin task/improve-bridge-logging
gh pr create --base main --head task/improve-bridge-logging --fill
```

Complete every section of the generated PR template. The Worker stops at the
PR; it does not merge. The handoff must explicitly say implementation and
self-review are complete, list tests, and identify remaining risks.

## Review and integration

The Review Agent reviews without modifying code by default. It uses
[`agent-templates/reviewer-prompt.md`](agent-templates/reviewer-prompt.md),
reviews the whole diff and relevant tests, and reports all blocking findings in
one batch rather than stopping at the first bug. It keeps the standard
Blockers/Important issues/Minor issues sections, labels non-blocking findings
as follow-ups, and returns `APPROVE` or `REQUEST CHANGES`.
The Integration / Lead Agent resolves dependencies and API contracts before
parallel work starts, then performs the approved **Squash and merge**.

The normal limit is one review, an optional consolidated fix, and one
verification review. Three `REQUEST CHANGES` decisions in the same module stop
incremental patching and trigger invariant/model reassessment.

After the merge is visible in `origin/main`, run this from the primary
checkout:

```bash
./script/cleanup-task-worktree.sh \
  task/improve-bridge-logging \
  ../TouchCode-worktrees/improve-bridge-logging
```

It refuses cleanup unless GitHub reports that the task PR merged into `main`.
That check is necessary for squash merges, where the task branch itself is not
an ancestor of `main`. It then removes the worktree and local branch and
fast-forwards local `main`. Delete the remote branch via the merged PR setting
or a separate, explicitly authorized command.

## Parallelism boundary

Split concurrent tasks by module ownership. If two tasks need the same public
API, protocol, or architecture decision, have the Lead establish that contract
first. A Worker that discovers scope-expanding architecture or public API work
records it in the PR and asks the Lead to decide; it does not silently broaden
the task.

## Operational budgets

- Check worktree state after creation, at Worker delivery, and before cleanup.
- Check remote branch SHA before review and approved PR-head SHA before merge.
- Treat GitHub EOF/timeouts as temporary; continue local work until a real gate.
- Do not use empty commits, force-push, or repeated API polling for sync.
- Target one worktree, one branch, one PR, one implementation pass, at most two
  review rounds, at most two full validation runs, and zero or one Sol call.

Progress language must distinguish prerequisites, implementation, review,
merge, and validation. “Worktree created” means implementation can start; it
does not mean the feature is complete.

## Test selection matrix

Choose the narrowest command that exercises the changed boundary, then widen
only at the pre-review and pre-merge gates.

| Changed area | Inner loop | Pre-review | Pre-merge when affected |
| --- | --- | --- | --- |
| Protocol schemas/types | `pnpm --filter @touchcode/protocol test` | protocol `check`, `test`, and `build` | root `pnpm check`, `pnpm test`, `pnpm build` |
| Mac Bridge runtime | `pnpm --filter @touchcode/mac-bridge-runtime exec tsx --test test/<name>.test.ts` | Bridge runtime `check` and `test` | root checks/build plus the justified integration smoke |
| Demo web UI | `pnpm --filter @touchcode/demo-web check` | demo `check` and `build` | root checks/build and relevant visual/manual verification |
| iPad networking/session | Xcode `-only-testing:TouchCodeTests/TouchCodeNetworkingTests` | affected XCTest classes and simulator build | full relevant Xcode test destination; physical-device checks only when acceptance requires them |
| iPad annotation/gesture | matching `AnnotationDraftTests` or `HMRAndGestureTests` class | affected XCTest classes and simulator build | full relevant Xcode test destination plus explicitly required device interaction |
| Workflow docs/scripts | syntax, fixture, link, and `git diff --check` checks | all affected workflow script fixtures | no product build unless executable product files changed |

Use the exact Xcode destination and environment from
[`install_guide.md`](../install_guide.md). Simulator, mock provider, build, and
physical-device evidence remain separate validation layers.
