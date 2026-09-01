# Multi-Agent Git workflow

TouchCode uses one task, one worktree, one branch, and one Pull Request.
`AGENTS.md` is the authoritative rule set; this page is the practical
reference for a task lifecycle.

## Worker quick start

From the primary `main` checkout, create an isolated task checkout:

```bash
./script/create-task-worktree.sh improve-bridge-logging
cd ../TouchCode-worktrees/improve-bridge-logging
```

The script fetches `origin/main`, creates `task/improve-bridge-logging`, and
attaches that branch to the new worktree. Make all changes there. Do not start
implementation in the primary checkout.

Before delivery, commit atomically, run the relevant checks from
[`install_guide.md`](../install_guide.md), and inspect:

```bash
git diff --check
git diff origin/main...HEAD
git push -u origin task/improve-bridge-logging
gh pr create --base main --head task/improve-bridge-logging --fill
```

Complete every section of the generated PR template. The Worker stops at the
PR; it does not merge.

## Review and integration

The Review Agent reviews without modifying code by default, and reports
Blockers, Important issues, Minor issues, plus `APPROVE` or `REQUEST CHANGES`.
The Integration / Lead Agent resolves dependencies and API contracts before
parallel work starts, then performs the approved **Squash and merge**.

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
