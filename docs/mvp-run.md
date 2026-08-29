# TouchCode two-device MVP

## What this slice proves

The Mac application starts the local bridge and prepares an isolated React/Vite
workspace. The iPad loads that site directly in `WKWebView`. Apple Pencil ink is
kept as raw drawing data and composited onto a fresh webpage screenshot only
when the user submits a request. The bridge saves that image inside the isolated
workspace and invokes Codex with:

- the annotated image;
- the text instruction;
- visible DOM rectangles and React source hints.

Codex edits the demo workspace and Vite HMR updates the page already open on the
iPad. TouchCode does not classify circles, arrows, or strike-through gestures.

## Prerequisites

- macOS 14 or later.
- Node.js 22 and pnpm.
- Full Xcode with an iPadOS 18 SDK.
- An iPad and Mac on the same local network.
- A working local Codex login for `@openai/codex-sdk`.

## Manual run

1. At the repository root, install workspace dependencies with `pnpm install`.
2. Launch the Mac application with `./script/build_and_run.sh`.
3. In the Mac app, click **Start MVP Demo** and wait for the LAN bridge and
   preview addresses to appear.
4. Open `apps/ipad/TouchCode.xcodeproj` in Xcode.
5. Choose your development team and a connected iPad, then run TouchCode.
6. Enter the Mac app's `http://<mac-lan-ip>:4317` bridge address and tap
   **Start MVP Session**.
7. Draw directly over an element. Tap the conversation bubble that appears by
   the ink, enter a change such as “Make this button black,” and submit.
8. Keep the iPad page open. When Codex completes, Vite HMR displays the source
   change without reconnecting.

The app requests local-network access on first use. Plain HTTP is intentional
for this same-LAN development MVP and must not be exposed to an untrusted
network.

## Deliberately deferred

- Bonjour/QR pairing and authenticated sessions.
- Selecting a real project and managing its dev-server command.
- Diff approval, Git rollback and change persistence.
- Voice input and GPT Realtime.
- Production signing, packaging and App Store distribution.
