# TouchCode MVP architecture

## Responsibility boundary

```text
iPad webpage + raw Pencil marks
  -> TouchCode Mac bridge
     -> selected CodingAgentProvider
        -> Codex / Claude Code / custom agent
     <- run events and code diff
  <- preview, status, keep or undo
```

TouchCode Mac does not pretend to be a coding agent and does not independently
decide how source code should change. It performs four product responsibilities:

1. Connect the iPad to the local development environment.
2. Package the annotated screenshot, visible DOM/React candidates and user
   instruction into a provider-neutral request. Gesture meaning is interpreted
   by the multimodal coding model, not by a local classifier.
3. Enforce project grants, worktree isolation and user change decisions.
4. Present provider progress, diff, preview and rollback controls.

## Mac application

The native SwiftUI application is the user-facing control plane. It displays:

- bridge and iPad connection status;
- authorized project and preview status;
- the user-selected coding agent;
- coding run progress, diff, Keep and Undo controls.

The TypeScript bridge runtime is an internal component. It is separated from
the UI so the network and provider contracts can be tested without launching a
desktop window. Production packaging will start and supervise this runtime from
the Mac app.

## Coding agent providers

`CodingAgentProvider` is the only interface the bridge uses to invoke a coding
agent. The first implementation uses the official Codex SDK with a
workspace-write sandbox, no network access and no interactive approvals. Future
Claude Code or custom adapters must implement the same provider-neutral result
and event types.

The provider receives a granted worktree path, edit intent, annotated image and
supporting visible-element context.
It never receives authority to modify the original project directly.

## Current limitations

- The runnable slice uses a generated isolated demo workspace, not arbitrary
  user-selected projects yet.
- Diff review, Keep, Undo and durable run history are not wired into the UI.
- Pairing currently uses a manually entered LAN address and has no authentication.
- Voice and GPT Realtime are not part of this text-plus-image MVP.
- The iPad target requires full Xcode and has not been built in this environment.
