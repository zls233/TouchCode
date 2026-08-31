# TouchCode

TouchCode is an iPad-to-Mac visual webpage editing MVP. The supported editing
path runs through the foreground Mac CLI. A native Mac control app can also be
built and launched locally, but it is a separate demo/control surface and is
not required for the iPad flow.

## Installation and startup

Humans and coding agents should use
[`install_guide.md`](install_guide.md) as the canonical installation, startup,
verification, and troubleshooting entry point. In particular, follow its
acceptance checklist before reporting that TouchCode is fully running.

## Implemented flow

1. The CLI verifies a clean Git repository and creates an isolated detached worktree.
2. The CLI starts the project's existing preview command and prints a LAN address plus pairing code.
3. The iPad opens the webpage, and Apple Pencil ink is composited onto a screenshot.
4. The user types an instruction or optionally taps the microphone to transcribe
   one. Voice input is wired into the composer and is sent as `inputMode: "voice"`;
   the repository has not verified microphone permissions or speech recognition
   on a physical iPad.
5. The bridge sends the annotated JPEG and instruction text directly to the Codex SDK.
6. Codex edits only the isolated worktree; the existing dev server/HMR can
   update the preview already open on the iPad after completion. The client does
   not issue a separate forced reload.

The iPad optionally reads visible-element context from the preview's
`window.touchCodeBridge.visibleContext()` hook; without that hook, the request
contains an empty context list and the model uses the screenshot and repository
contents. This flow does not accept video and does not use GPT Realtime. Diff,
Keep, Undo, and merging changes back to the source repository are outside the
CLI MVP.

## Quick start

The complete procedure, including prerequisites, Xcode selection, simulator
tests, physical-iPad setup, optional Mac app startup, and evidence boundaries,
is in [`install_guide.md`](install_guide.md).

Install dependencies:

```bash
pnpm install --frozen-lockfile
```

Start TouchCode against a clean Git web project. Everything after `--` is the
project's normal preview command:

```bash
pnpm touchcode \
  --project /absolute/path/to/web-project \
  --cwd . \
  --preview-port 5173 \
  -- pnpm dev -- --host 0.0.0.0 --port 5173
```

Then build/run `apps/ipad/TouchCode.xcodeproj` on an iPad or simulator, and
enter the bridge address and six-digit code printed by the CLI. The checked-in
build wrapper is intended for simulator compilation; simulator launch and
local loopback tests do not prove a complete physical-iPad/LAN UI flow.

See [`install_guide.md`](install_guide.md) first and
[`docs/mvp-run.md`](docs/mvp-run.md) for additional CLI safety behavior and
current limitations.
