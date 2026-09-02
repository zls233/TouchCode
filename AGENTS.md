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

Use this default target: one investigation, one complete task packet, one
implementation pass, one Worker self-review, one independent review, and at
most one consolidated fix pass. More loops require a specific reason.

1. Inspect the branch, diff, and current baseline once; preserve all user
   changes.
2. Classify the task risk and freeze its scope.
3. Read the relevant implementation, interfaces, tests, configuration, and
   approved plan in one batch, then write a complete task packet.
4. Let Luna complete one bounded, verifiable development slice and self-review
   it before external review.
5. Escalate through a task packet only when the routing criteria apply.
6. Run targeted checks during implementation, affected-package checks before
   review, and full validation only at the pre-merge gate.
7. Evaluate the acceptance result, regression risk, unverified paths, and next
   slice without repeating completed investigation or validation.

### Risk levels

- **Level 1 — Routine:** single-file bugs, small UI/config/copy changes, direct
  compiler errors, tests, and simple refactors. Use Luna, targeted tests, and a
  lightweight diff review. Do not use Sol or an exhaustive state matrix.
- **Level 2 — Stateful / Cross-module:** sessions, networking, async work,
  reconnect, cache/persistence lifecycle, state machines, and multi-module
  APIs. Lead defines invariants; Worker performs full lifecycle self-review;
  Reviewer performs one complete state/race review.
- **Level 3 — Architecture / Security:** cryptography, trust boundaries,
  protocol architecture, destructive migration, irreversible formats, and
  cross-platform core architecture. Sol decides only the smallest necessary
  architecture question; Lead freezes that decision before Luna implements.

The Lead performs one concentrated investigation at task start: status/fetch,
the necessary source and tests, and the relevant plan. Do not repeatedly poll
Git, GitHub, or reread files unless implementation reveals genuinely new
information.

### Task packet

Every modifying task starts from a single packet containing: Outcome, risk
level, Allowed Scope, Do Not Touch, Relevant Files, Invariants, Known Edge
Cases, Acceptance Criteria, and the three validation tiers. Use
[`docs/agent-templates/task-packet.md`](docs/agent-templates/task-packet.md).
If the packet changes after implementation starts, the Lead must explicitly
re-freeze scope.

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
4. Treat the accepted task packet as a scope freeze. Record unrelated findings
   as follow-ups unless they directly block acceptance. Keep commits atomic
   and use conventional commits:
   `<type>(<scope>): <short description>`.
5. Use three validation tiers: targeted tests/typecheck in the inner loop;
   targeted plus affected-package tests before review; full repository,
   Xcode, or integration validation only before merge when relevant. Follow
   [`install_guide.md`](install_guide.md) and record exact commands/results.
6. Before independent review, self-review the complete
   `git diff origin/main...HEAD` using
   [`docs/agent-templates/worker-self-review.md`](docs/agent-templates/worker-self-review.md).
   For Level 2 work, cover happy/failure paths, start/stop/retry/reconnect,
   reentrancy, stale callbacks/generations, ownership, cleanup, and deterministic
   tests. Async lifecycle tests should prefer controllable fakes with explicit
   enter/pause/resume/fail/complete control over immediate no-op mocks.
7. Run `git diff --check`, then report `Implementation complete`, `Self-review
   complete`, tests run, and known remaining risks. Only then request review.
8. Push only the task branch, set its upstream, and create a PR targeting
   `main`. The PR is the standard Worker delivery. Never push directly to
   `main`, force-push, rebase interactively, merge a PR, or rewrite history.

Use [`.github/pull_request_template.md`](.github/pull_request_template.md) for
every PR. It requires Summary, Changes, Validation, API Changes, and Risks /
unresolved issues.

### Review and integration

Review intensity follows the risk level: Level 1 gets a lightweight diff
review, Level 2 gets a full state/lifecycle review, and Level 3 gets a
security/architecture review against the frozen decision. Review Agents read
the complete diff and related state machine/tests, build the edge-case list,
and return all high-confidence findings together. They do not stop after the
first issue unless it is a fatal architecture error.

Classify correctness, data loss, realistic races, security, regressions, and
broken workflow as `Blocking`. Classify cleanup, future optimization, better
abstraction, unrelated refactors, and purely hypothetical edges as
`Follow-up`; follow-ups do not block the PR. Preserve the standard output
sections `Blockers`, `Important issues`, and `Minor issues`, and label
non-blocking findings as follow-ups. Use
[`docs/agent-templates/reviewer-prompt.md`](docs/agent-templates/reviewer-prompt.md).
Review Agents remain read-only unless the Lead assigns a separate fix task.

Normal review is one exhaustive pass followed by zero or one consolidated fix
pass and one verification review. If the same module receives three
`REQUEST CHANGES` decisions, stop incremental patching: the Lead must redefine
the missing invariants, reassess the whole implementation, and use Sol only if
the repeated failure meets the escalation criteria.

During implementation, the remote task branch is the source of truth. Check
the remote/reviewed SHA once before review and the PR-head/approved SHA once at
the merge gate. Do not poll `gh pr view`, PR refs, checks, or worktree state
between gates. On GitHub EOF, timeout, or ref delay, confirm the branch push and
continue local work until the next gate; never create empty commits or force
push to provoke synchronization.

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

### Baselines, migrations, and status reporting

If `origin/main` lacks a required local baseline, either submit one verified
baseline PR first or pause feature work for one Baseline Stabilization task.
Do not interleave both contexts. A one-time historical migration PR may contain
multiple existing atomic commits and may use a merge commit, but its body must
state `PR type: migration` and `Exception: one-time`.

Check worktree state only after creation, at Worker delivery, and before
cleanup unless a real conflict appears. Progress updates should be limited to
blockers, Worker start/completion, material review findings, PR readiness, and
merge completion. Report phases precisely as prerequisite complete,
implementation started/completed, review completed, merged, or validated.

Normal targets are one task branch/worktree/PR, one Worker implementation pass,
no more than two independent review rounds, no more than two full repository
validation runs, and zero or one Sol decision.
