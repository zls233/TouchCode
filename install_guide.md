# TouchCode installation and startup guide

This file is the canonical installation and startup procedure for humans and
coding agents. Run commands from the repository root unless a step explicitly
says otherwise. Do not invent a different startup path before checking this
guide and the current scripts.

## 1. Prerequisites

- macOS 14 or newer.
- Git.
- Node.js 22 or newer.
- pnpm 10.28.2. Corepack can install the repository-pinned version.
- A full Xcode installation. The checked-in scripts default to
  `/Applications/Xcode-beta.app/Contents/Developer`; set `DEVELOPER_DIR` when
  Xcode is installed elsewhere.
- For the complete iPad flow: a physical iPad and Mac on the same trusted local
  network, plus an Apple Developer signing team configured in Xcode.
- For live Coding Agent edits: a local Codex login usable by
  `@openai/codex-sdk`.

Check the local toolchain:

```bash
git --version
node --version
corepack --version
xcodebuild -version
```

Node must report version 22 or newer. If `pnpm` is unavailable or has the wrong
version, enable the version declared in `package.json`:

```bash
corepack enable
corepack prepare pnpm@10.28.2 --activate
pnpm --version
```

## 2. Install repository dependencies

```bash
pnpm install --frozen-lockfile
```

TouchCode does not install dependencies in the separate web project that it
opens. Install and verify that project's dependencies independently.

## 3. Verify the checkout

Run the repository checks before starting an interactive session:

```bash
pnpm check
pnpm test
pnpm build
```

Build the iPad target for the default simulator:

```bash
./script/build_ipad.sh
```

If the installed Xcode is not Xcode Beta, override the path without changing
the system-wide `xcode-select` setting:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/build_ipad.sh
```

To select another simulator, obtain its identifier and pass an explicit
destination:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl list devices available
TOUCHCODE_XCODE_DESTINATION='platform=iOS Simulator,id=SIMULATOR_ID' ./script/build_ipad.sh
```

## 4. Start the supported TouchCode flow

The supported iPad editing flow uses the foreground Mac CLI. The target web
project must already run successfully, be a Git repository, and have a clean
working tree. Everything after `--` is that project's normal preview command.

```bash
pnpm touchcode \
  --project /absolute/path/to/web-project \
  --cwd . \
  --preview-port 5173 \
  -- pnpm dev -- --host 0.0.0.0 --port 5173
```

For a monorepo preview package, change `--cwd .` to its repository-relative
directory, for example `--cwd apps/web`. Keep this terminal running. TouchCode
prints the Bridge URL, six-digit pairing code, and isolated worktree path.

The CLI intentionally refuses a dirty source repository, a detached source
checkout, an invalid `--cwd`, or an occupied preview port. Fix the reported
condition instead of bypassing the guard.

## 5. Launch and connect the iPad app

### Physical iPad (required for final hardware acceptance)

1. Open `apps/ipad/TouchCode.xcodeproj` in Xcode.
2. Select the `TouchCode` scheme and the connected iPad.
3. Configure the signing team for bundle identifier `com.touchcode.ipad`.
4. Build and run the app.
5. Enter the Bridge URL and pairing code printed by the Mac CLI.
6. Accept Local Network, Microphone, and Speech Recognition permissions when
   prompted.

The Mac and iPad must be on the same trusted network. Use the Mac's LAN address
printed by the CLI, not `127.0.0.1` or `localhost`.

### Simulator

The simulator is suitable for compilation, unit tests, and basic UI checks. It
does not prove Apple Pencil behavior, physical-device LAN connectivity, or real
microphone and Speech Recognition behavior.

Open the project in Xcode and run the selected simulator, or run tests from the
command line:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project apps/ipad/TouchCode.xcodeproj \
  -scheme TouchCode \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=SIMULATOR_ID' \
  -derivedDataPath DerivedData/TouchCode-iPad \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## 6. Optional native Mac control app

The native Mac app is a separate demo/control surface. It is not required for
the supported foreground CLI plus iPad flow.

Build and launch it with:

```bash
./script/build_and_run.sh run
```

Other supported modes are `debug`, `logs`, `telemetry`, and `verify`:

```bash
./script/build_and_run.sh verify
```

## 7. Stop and restart

- Press Control-C in the CLI terminal to stop the Bridge and preview process.
- TouchCode preserves the isolated worktree and prints its path for inspection.
- Before restarting, confirm the preview port is free and the target source
  repository remains clean.
- Do not delete preserved worktrees or user changes automatically.

## 8. Agent acceptance checklist

An agent must not report the project as fully running after only opening a port
or compiling one target. Report each verified layer separately:

1. `pnpm install --frozen-lockfile` completed.
2. `pnpm check`, `pnpm test`, and `pnpm build` completed.
3. The iPad target compiled, and the exact Xcode destination was recorded.
4. The CLI started against a clean test web project and printed pairing data.
5. The preview and authenticated Bridge API were exercised.
6. The iPad paired and displayed the preview.
7. On a physical iPad, Pencil, scrolling/zooming, two-finger voice gestures,
   microphone permission, transcription, and a real edit were exercised.

If a layer cannot be verified, state it as unverified. Simulator success is not
physical-iPad acceptance, and mock-provider success is not a live Codex edit.

For detailed CLI behavior and evidence boundaries, also see
[`docs/mvp-run.md`](docs/mvp-run.md).
