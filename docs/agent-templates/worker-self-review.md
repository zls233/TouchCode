# Worker self-review

Review the entire task diff with a reviewer mindset before external review.
Try to break the implementation and update code/tests before handoff.

## Every task

- [ ] Acceptance criteria are satisfied without scope creep.
- [ ] Happy and realistic failure paths are covered.
- [ ] Public/protocol/API changes are intentional and documented.
- [ ] Tests reproduce the behavior rather than merely execute code.
- [ ] Resources and partial state are cleaned up.
- [ ] `git diff origin/main...HEAD` contains only task-owned changes.
- [ ] `git diff --check` passes.

## Level 2 and Level 3 additions

- [ ] Start, stop, retry, reconnect, and repeated invocation are coherent.
- [ ] Delayed completions and stale callbacks cannot mutate newer state.
- [ ] Cancellation and generation/ownership changes are safe.
- [ ] Reentrancy and replacement operations are deterministic.
- [ ] Important races use a controllable fake with enter/pause/resume/fail or
      complete control.

## Required handoff

```text
Implementation complete: yes
Self-review complete: yes
Tests: <commands and results>
Known remaining risks: <none or concise list>
```
