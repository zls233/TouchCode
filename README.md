# TouchCode

TouchCode connects an iPad interaction surface to coding agents running on a Mac.

The Mac component is a **bridge application**, not an AI agent. It owns device
pairing, project permissions, browser context, previews, worktrees and change
review. Codex, Claude Code or another user-selected coding agent owns code
reasoning and editing.

## Current vertical slice

- Native SwiftUI TouchCode Mac shell.
- Mac-managed local bridge runtime and isolated demo workspaces.
- Native iPadOS SwiftUI project with full-screen `WKWebView` preview.
- PencilKit overlay that composites raw handwriting onto the webpage screenshot.
- Visible DOM/React context collection without local gesture classification.
- Provider boundary for multiple coding agents.
- Multimodal Codex integration through the official `@openai/codex-sdk` package.
- Vite HMR preview that reflects Codex edits back on iPad.

## Run locally

Install dependencies once, then build and launch the native Mac app:

```bash
pnpm install
./script/build_and_run.sh
```

Click **Start MVP Demo**, then open `apps/ipad/TouchCode.xcodeproj` in Xcode,
run it on an iPad, and enter the LAN bridge address shown by the Mac app. See
[`docs/mvp-run.md`](docs/mvp-run.md) for the complete manual flow.

## Architectural vocabulary

- **TouchCode iPad:** live preview, raw Pencil annotation and text intent.
- **TouchCode Mac:** user-facing bridge and control application.
- **Bridge Runtime:** local transport and permission service managed by the Mac app.
- **Coding Agent:** Codex, Claude Code or another external system that changes code.
