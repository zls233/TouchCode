# Task worktree workflow

TouchCode uses one task, one worktree, one branch, and one Pull Request. The
efficiency target is one batched investigation, one implementation pass,
targeted tests, one self-review, and one PR.

## Start gate

Confirm the scope before creating a worktree. Read the Git baseline, approved
plan, relevant implementation, interfaces, tests, and configuration in one
batch. Complex tasks can use
[`agent-templates/task-packet.md`](agent-templates/task-packet.md) to record
invariants and validation tiers. After implementation starts, scope is frozen.

## Quick start

From the primary `main` checkout, create an isolated task checkout:

```bash
./script/create-task-worktree.sh improve-bridge-logging
cd ../TouchCode-worktrees/improve-bridge-logging
```

The script fetches `origin/main`, creates `task/improve-bridge-logging`, and
attaches that branch to the new worktree. Make all changes there.

During implementation, run targeted checks. Before PR delivery, run targeted
and affected-package checks. Reserve full repository, Xcode, and integration
gates for pre-merge when the scope requires them. Complete
[`agent-templates/self-review.md`](agent-templates/self-review.md), commit
atomically, and inspect:

```bash
git diff --check
git diff origin/main...HEAD
git push -u origin task/improve-bridge-logging
gh pr create --base main --head task/improve-bridge-logging --fill
```

Complete every PR template section. The handoff must say implementation and
self-review are complete, list tests, identify remaining risks, and record the
delivery branch SHA. Do not merge the task's own PR.

## Merge and cleanup

Use **Squash and merge**. At the merge gate, check the intended PR-head SHA and
required CI checks once. After the merge is visible in `origin/main`, run from
the primary checkout:

```bash
./script/cleanup-task-worktree.sh \
  task/improve-bridge-logging \
  ../TouchCode-worktrees/improve-bridge-logging
```

The script verifies that GitHub reports the task PR merged into `main`, removes
the worktree and local branch, and fast-forwards local `main`.

## Operational budgets

- Check worktree state after creation, at task delivery, and before cleanup.
- Treat GitHub EOF/timeouts as temporary; continue local work until a real gate.
- Do not use empty commits, force-push, or repeated API polling for sync.
- Target one worktree, one branch, one PR, one implementation pass, one
  self-review, and no more than two full validation runs.

Progress language must distinguish prerequisites, implementation, PR delivery,
merge, and validation. “Worktree created” only means implementation can start.

## Test selection matrix

Choose the narrowest command that exercises the changed boundary, then widen
only at the pre-delivery and pre-merge gates.

| Changed area | Inner loop | Pre-delivery | Pre-merge when affected |
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
