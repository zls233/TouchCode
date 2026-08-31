# Run the TouchCode CLI MVP

## Prerequisites

- macOS with Node.js 22+, pnpm, Git, and Xcode.
- A web project that is already runnable and committed with a clean Git status.
- A local Codex login usable by `@openai/codex-sdk`.
- Mac and iPad on the same trusted local network.

## Start the Mac CLI

From this repository:

```bash
pnpm install
pnpm touchcode \
  --project /absolute/path/to/your-web-project \
  --cwd . \
  --preview-port 5173 \
  -- pnpm dev -- --host 0.0.0.0 --port 5173
```

Use `--cwd apps/web` when the preview package lives in a monorepo subdirectory.
The preview command is executed directly, without a shell. TouchCode also sets
`HOST=0.0.0.0` and `PORT` for frameworks that read those variables.

The CLI refuses a dirty repository, detached source checkout, a `--cwd` outside
the repository, or an occupied preview port. It creates a detached worktree under
`~/Library/Application Support/TouchCode/worktrees` and reuses existing
`node_modules` through local symlinks when available; it never installs project dependencies.

## Connect the iPad

1. If `xcode-select -p` reports CommandLineTools, use the repository-local
   Xcode wrapper below. It sets `DEVELOPER_DIR` for this command only and does
   not change the system-wide developer directory:

   ```bash
   ./script/build_ipad.sh
   # Or choose another installed Xcode explicitly:
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/build_ipad.sh
   ```

   The script prefers an iPad Pro 13-inch (M5), then an iPad Pro 11-inch (M5),
   then any available iPad simulator. Override it with
   `TOUCHCODE_XCODE_DESTINATION='platform=iOS Simulator,id=SIMULATOR_ID'`
   when needed. For device signing and launch, open
   `apps/ipad/TouchCode.xcodeproj` in Xcode and run it on an iPad.
2. Enter the `Bridge` URL and six-digit `Pairing code` printed by the CLI.
3. Use the pencil button to switch between webpage interaction and annotation.
4. Draw on the webpage screenshot.
5. Type a request, or tap the microphone to transcribe one. The iPad composer
   sends voice-originated text with `inputMode: "voice"`; microphone permission,
   speech recognition, and the permission prompt still require physical-device
   verification and are not part of the verified run path.
6. Tap **Update**. Keep both the CLI and preview command running.
7. When Codex succeeds, the dev server/HMR can update the preview already open
   on the iPad; the client clears the submitted ink and instruction. No separate
   forced reload is issued by the client.

Stopping with Ctrl-C terminates the preview and Bridge but preserves the isolated
worktree. The CLI prints that worktree path so it can be inspected manually.

## Security and evidence boundary

Pairing creates a high-entropy per-session token; every session request requires
it. Plain HTTP is limited to this trusted-LAN MVP. The Bridge rejects non-JPEG
image uploads and caps request size. A completed automated test with a mock
provider proves transport and orchestration, but it is not evidence of a paid,
live Codex edit, a complete physical-iPad/LAN UI flow, or real Apple Pencil
hardware behavior. The local simulator build/launch and loopback pairing
checks are narrower evidence: they cover compilation, process startup, and
HTTP contracts, not end-to-end visual interaction on a physical device.
