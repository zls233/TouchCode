# TouchCode CLI MVP architecture

```text
iPad WKWebView + Pencil screenshot + typed text
  -> authenticated LAN Bridge
     -> Codex SDK with local_image
        -> isolated Git worktree
        -> existing dev server / HMR
  <- run status and dev-server-refreshed webpage
```

## Boundaries

- The iPad captures one current-viewport JPEG with raw Pencil marks composited on top.
- The current editing composer accepts typed text and optional speech
  transcription. Voice-originated text is marked `inputMode: "voice"` in the
  existing protocol; physical-device microphone permission and recognition remain
  unverified.
- The iPad attempts to read optional visible-element context from the preview's
  `window.touchCodeBridge.visibleContext()` hook. If the hook is absent, it sends
  an empty context list; there is no guaranteed DOM-to-source mapping.
- The Bridge stores input images outside the editable worktree and passes their local paths to Codex.
- Codex runs with workspace-write access, no network, and no interactive approvals.
- The original source checkout must be clean and is never the coding agent's working directory.
- The created detached worktree is preserved after the CLI exits so changes remain inspectable.

There is no required webpage instrumentation or guaranteed mapping from visual
marks to DOM nodes, framework components, selectors, or source locations. When
the optional context hook is available, its visible-element data is included as
additional model input; the model still uses the image and repository contents
to infer the requested source change.

## Deferred

- Video input and GPT Realtime.
- A fuller native Mac control application beyond the current local demo/control surface.
- Diff review, Keep/Undo, and merging worktree changes back to the source branch.
- Remote internet transport, durable sessions, QR/Bonjour discovery, and production packaging.
