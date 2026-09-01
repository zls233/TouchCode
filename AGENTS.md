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

## Multi-Agent Git workflow

The repository workflow is **one task, one worktree, one branch, one Pull
Request**. A worktree belongs to a task, not to an individual agent. Do not
reuse a completed task worktree for unrelated work.

### Roles

- **Worker Agent** implements one bounded task, tests it, and delivers a Pull
  Request (PR). It must not merge its own PR.
- **Review Agent** is read-only by default. It reviews the PR and reports only
  `Blockers`, `Important issues`, `Minor issues`, and either `APPROVE` or
  `REQUEST CHANGES`.
- **Integration / Lead Agent** decomposes work by module ownership, establishes
  shared API/architecture decisions before dependent tasks run in parallel,
  coordinates review and performs the final integration/merge.

Read-only investigation, planning, and review do not require a separate
worktree. Every task that changes code, tests, tracked documentation, or build
configuration does.

### Worker Agent procedure

1. Inspect `git status --short --branch`, `git worktree list`, and the task
   scope before starting. Preserve unrelated changes.
2. From the repository's primary checkout, fetch `origin/main` and create a
   task branch named `task/<short-task-name>` from the latest `origin/main`.
   Create a separate worktree for that branch. Use
   `./script/create-task-worktree.sh <short-task-name>` unless the Lead has
   supplied an already-created task worktree.
3. Change code **only** in that task worktree; never develop in the `main`
   worktree. Keep the task's file ownership narrow. If tasks overlap heavily,
   serialize them. If they have an API or architecture dependency, the Lead
   must settle the shared contract before workers start implementation.
4. Keep commits atomic and use conventional commits:
   `<type>(<scope>): <short description>`.
5. Run the smallest relevant checks, then broader checks required by
   [`install_guide.md`](install_guide.md) when the task crosses package/app
   boundaries. Record commands and results; do not equate a build with a
   complete device or end-to-end validation.
6. Self-review `git diff origin/main...HEAD` and `git diff --check`. Do not
   expand the task into a broad refactor or public API change. Escalate such a
   need to the Lead and record it in the PR instead.
7. Push only the task branch, set its upstream, and create a PR targeting
   `main`. The PR is the standard Worker delivery. Never push directly to
   `main`, force-push, rebase interactively, merge a PR, or rewrite history.

Use [`.github/pull_request_template.md`](.github/pull_request_template.md) for
every PR. It requires Summary, Changes, Validation, API Changes, and Risks /
unresolved issues.

### Review and integration

Review Agents check acceptance criteria, bugs, regressions, race conditions,
lifecycle behavior, scope creep, API changes, test coverage, and unnecessary
refactors. They do not modify the Worker branch unless the Lead explicitly
assigns a follow-up implementation task.

The Lead merges approved PRs using **Squash and merge**, so `main` contains one
clean commit describing the final task outcome rather than temporary Worker
commits. Because a squash commit does not retain the task branch as an
ancestor, after merge the Lead verifies the GitHub PR is merged into `main`,
removes the task worktree, deletes the task branch, and updates the local
`main` checkout. Use
`./script/cleanup-task-worktree.sh task/<short-task-name> <worktree-path>` for
the local cleanup after that verification.

`git push`, deleting remote branches, merge actions, and destructive cleanup
remain external-state changes. They require explicit user or Lead integration
authorization. Never reset, overwrite, delete, publish, purchase, or call paid
external providers without that authorization.
