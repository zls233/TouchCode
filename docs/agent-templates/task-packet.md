# Task packet — cancelled

> This template is **cancelled** and retained only for historical reference.
> Do not create a Task Packet / Tech Packet for new tasks.

Effective workflow (see `AGENTS.md`):

- Task context is only the user's current instruction + `AGENTS.md` + `Plan.md`
  (if present). `Plan.md` is optional.
- Do not create, require, or gate on any packet document. Do not block
  implementation waiting for packet approval.
- Freeze scope from the current instruction; re-freeze explicitly if it changes.
- Implement the minimal change that satisfies the current Acceptance Criteria.
  No scope expansion or over-design.
- Record out-of-scope findings only as follow-ups — never implement inline.
- Sol is only a temporary advisor for complex problems that cannot be safely
  decided from the available context; not a default reviewer or required gate.

For validation, use the three tiers defined in `AGENTS.md` and
`docs/task-worktree-workflow.md` (targeted → affected-package → full pre-merge)
without requiring a packet.
