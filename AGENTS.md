# TouchCode agent workflow

## Installation and startup

Before installing dependencies, building, starting, debugging, or claiming the
project is running, read and follow [`install_guide.md`](install_guide.md). Treat
it as the canonical command sequence and acceptance checklist. If repository
scripts or package metadata conflict with the guide, inspect the current source,
update the guide in the same change, and report the discrepancy.

Do not claim a complete run from a successful build or open port alone. Keep
dependency installation, checks, Mac CLI/Bridge startup, authenticated API,
iPad pairing, simulator verification, and physical-device verification as
separate evidence.

## Development loop

Target one batched investigation, one implementation pass, targeted
validation, one complete self-review, and one PR.

1. Inspect the branch, diff, and current baseline once; preserve all user
   changes.
2. Confirm and freeze the explicit task scope directly from the user's current
   instruction (plus `AGENTS.md` / `Plan.md` if provided).
3. Read the relevant implementation, interfaces, tests, configuration, and
   `Plan.md` (if present) in one batch. Do not require or create a Task Packet.
4. Complete one bounded, verifiable development slice with the minimal
   implementation that satisfies the current Acceptance Criteria and self-review
   it. Do not expand scope or over-design.
5. Run targeted checks during implementation, affected-package checks before
   PR delivery, and full validation only at the pre-merge gate when justified.
6. Evaluate the acceptance result, regression risk, unverified paths, and next
   slice without repeating completed investigation or validation. Record
   out-of-scope items only as follow-ups.

Perform one concentrated investigation at task start: status/fetch, the
necessary source and tests, and the relevant plan (`Plan.md` if present). Do
not repeatedly poll Git, GitHub, or reread files unless implementation reveals
genuinely new information.

### Task packet — cancelled

Task Packet / Tech Packet and any related mandatory packet documents are
cancelled. Do not create them, do not require them as a gate, and do not block
implementation waiting for them. The only task context is: the user's current
instruction + `AGENTS.md` + `Plan.md` (if present). `Plan.md` is optional
reference material, not a required deliverable.

### Scope and minimal implementation

- Freeze scope directly from the user's current instruction (plus `AGENTS.md` /
  `Plan.md` if provided). If scope changes mid-task, re-freeze explicitly.
- Always implement the minimal change that satisfies the current Acceptance
  Criteria. No opportunistic refactoring, no scope expansion, no over-design.
- Out-of-scope findings, improvement ideas, or unrelated risks are recorded
  only as follow-ups — never implemented inline.

### Advisor (Sol) — temporary only

Sol is not a default reviewer or required gate. Engage Sol only as a temporary
advisor when the current task encounters a complex problem that cannot be safely
decided with the available context (user instruction + `AGENTS.md` + `Plan.md`
+ code/tests). Keep the consultation narrow, time-boxed, and focused on the
specific decision; do not hand off ownership.

## Development documentation

All development-facing Markdown artifacts created by an agent—including plans,
PRDs, architecture proposals, implementation notes, research, and acceptance
checklists—must be stored under [`development-docs/`](development-docs/), not
at the repository root, in `docs/`, or in a temporary directory.

`development-docs/` is intentionally Git-ignored. Treat it as local working
material: do not stage, commit, or push files from it. When a document becomes
durable product or contributor documentation, move or rewrite its approved
content in the appropriate tracked location (for example `README.md` or
`docs/`) as a separate, explicitly scoped change.

Use a type directory (`plans`, `prds`, `architecture`, `research`, `notes`, or
`acceptance`) and create one descriptive child directory per artifact:

```text
development-docs/<type>/YYYY-MM-DD--<area>--<topic>/<document>.md
```

`<area>` identifies the product surface or module, and `<topic>` is a concise,
kebab-case description. The date, area, and topic are required so agents can
identify the document's purpose without opening it. Preserve imported
documents verbatim unless the task explicitly asks to edit their contents.

## Git task workflow

The repository workflow is **one task, one worktree, one branch, one Pull
Request**. A worktree belongs to a task, not to an individual agent. Do not
reuse a completed task worktree for unrelated work.

Read-only investigation, planning, and review do not require a separate
worktree. Every task that changes code, tests, tracked documentation, or build
configuration does.

### Task procedure

1. Inspect `git status --short --branch`, `git worktree list`, and the task
   scope before starting. Preserve unrelated changes.
2. From the repository's primary checkout, fetch `origin/main` and create a
   task branch named `task/<short-task-name>` from the latest `origin/main`.
   Create a separate worktree for that branch. Use
   `./script/create-task-worktree.sh <short-task-name>` unless the task already
   has an assigned worktree.
3. Change code **only** in that task worktree; never develop in the `main`
   worktree. Keep the task's file ownership narrow.
4. Treat the accepted scope as frozen. Record unrelated findings
   as follow-ups unless they directly block acceptance. Keep commits atomic
   and use conventional commits:
   `<type>(<scope>): <short description>`.
5. Use three validation tiers: targeted tests/typecheck in the inner loop;
   targeted plus affected-package tests before PR delivery; full repository,
   Xcode, or integration validation only before merge when relevant. Follow
   [`install_guide.md`](install_guide.md) and record exact commands/results.
6. Before PR delivery, self-review the complete
   `git diff origin/main...HEAD` using
   [`docs/agent-templates/self-review.md`](docs/agent-templates/self-review.md).
   For stateful work, cover happy/failure paths, start/stop/retry/reconnect,
   reentrancy, stale callbacks/generations, ownership, cleanup, and deterministic
   tests. Async lifecycle tests should prefer controllable fakes with explicit
   enter/pause/resume/fail/complete control over immediate no-op mocks.
7. Run `git diff --check`, then report `Implementation complete`, `Self-review
   complete`, tests run, and known remaining risks.
8. Push only the task branch, set its upstream, and create a PR targeting
   `main`. The PR is the standard task delivery. Never push directly to
   `main`, force-push, rebase interactively, merge a PR, or rewrite history.

Use [`.github/pull_request_template.md`](.github/pull_request_template.md) for
every PR. It requires Summary, Changes, Validation, API Changes, Risks /
unresolved issues, and the delivered branch SHA.

### PR and integration

During implementation, the task branch is the source of truth. At the merge
gate, check the intended PR-head SHA and required CI checks once. Do not poll
`gh pr view`, PR refs, checks, or worktree state between gates. On GitHub EOF,
timeout, or ref delay, confirm the branch push and continue local work until
the next gate; never create empty commits or force push to provoke
synchronization.

Merge approved PRs using **Squash and merge**, so `main` contains one clean
commit describing the final task outcome rather than temporary task commits.
Because a squash commit does not retain the task branch as an ancestor, after
merge verify the GitHub PR is merged into `main`, remove the task worktree,
delete the task branch, and update the local `main` checkout. Use
`./script/cleanup-task-worktree.sh task/<short-task-name> <worktree-path>` for
the local cleanup after that verification.

`git push`, deleting remote branches, merge actions, and destructive cleanup
remain external-state changes. They require explicit user authorization. Never
reset, overwrite, delete, publish, purchase, or call paid external providers
without that authorization.

### Baselines, migrations, and status reporting

If `origin/main` lacks a required local baseline, either submit one verified
baseline PR first or pause feature work for one Baseline Stabilization task.
Do not interleave both contexts. A one-time historical migration PR may contain
multiple existing atomic commits and may use a merge commit, but its body must
state `PR type: migration` and `Exception: one-time`.

Check worktree state only after creation, at task delivery, and before cleanup
unless a real conflict appears. Progress updates should be limited to blockers,
implementation start/completion, PR readiness, and merge completion. Report
phases precisely as prerequisite complete, implementation started/completed,
PR ready, merged, or validated.

Normal targets are one task branch/worktree/PR, one implementation pass, one
self-review, and no more than two full repository validation runs.
