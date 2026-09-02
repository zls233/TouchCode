#!/usr/bin/env node
import { createBridgeApp } from "./app.js";
import { cliUsage, cliVersion, parseCliOptions } from "./cli-options.js";
import { DemoSessionManager, localIPv4Address } from "./demo-session-manager.js";
import { ProjectGrantStore } from "./project-grants.js";
import { prepareWorkspace, removeFailedWorkspace, startPreview } from "./project-workspace.js";
import { access } from "node:fs/promises";
import { BonjourRegistration } from "./bonjour-registration.js";
import { consumeHostIdentityFromEnvironment } from "./host-identity.js";

async function main() {
  const options = parseCliOptions(process.argv.slice(2));
  if ("help" in options) {
    console.log(cliUsage);
    return;
  }
  if ("version" in options) {
    console.log(`touchcode ${cliVersion}`);
    return;
  }

  const hostAddress = localIPv4Address();
  const bridgeURL = `http://${hostAddress}:${options.bridgePort}`;
  const hostIdentity = consumeHostIdentityFromEnvironment();
  const grants = new ProjectGrantStore();
  const sessions = new DemoSessionManager(grants, bridgeURL);
  let workspace: Awaited<ReturnType<typeof prepareWorkspace>> | undefined;
  let preview: Awaited<ReturnType<typeof startPreview>> | undefined;
  let app: Awaited<ReturnType<typeof createBridgeApp>> | undefined;
  let bonjour: BonjourRegistration | undefined;
  let ready = false;
  let shuttingDown = false;

  // Pre-validate project path exists before git operations for friendlier error
  try {
    await access(options.projectPath);
  } catch {
    throw new Error(`--project does not exist: ${options.projectPath}`);
  }
  // Early check for bridge port already in use
  const { default: net } = await import("node:net");
  const bridgeInUse = await new Promise<boolean>((resolve) => {
    const s = net.createConnection({ host: "127.0.0.1", port: options.bridgePort });
    s.once("connect", () => { s.destroy(); resolve(true); });
    s.once("error", () => resolve(false));
    s.setTimeout(500, () => { s.destroy(); resolve(false); });
  });
  if (bridgeInUse) throw new Error(`Bridge port ${options.bridgePort} is already in use (is TouchCode already running?)`);

  try {
    workspace = await prepareWorkspace({
      projectPath: options.projectPath,
      projectCwd: options.projectCwd,
    });
    preview = await startPreview({
      workspace,
      command: options.previewCommand,
      port: options.previewPort,
    });
    const session = await sessions.registerProjectSession({
      worktreePath: preview.worktreePath,
      previewURL: `http://${hostAddress}:${options.previewPort}`,
      port: options.previewPort,
      process: preview.process,
    });
    app = await createBridgeApp({
      grants,
      bridgeBaseURL: bridgeURL,
      demoSessions: sessions,
      ...(hostIdentity ? { hostIdentity } : {}),
    });
    await app.listen({ host: "0.0.0.0", port: options.bridgePort });
    bonjour = new BonjourRegistration(options.bridgePort);
    bonjour.start();
    ready = true;

    console.log("\nTouchCode CLI is ready");
    console.log(`Pairing code: ${session.pairingCode}`);
    console.log(`Bridge:       ${bridgeURL}`);
    console.log("Discovery:    Bonjour _touchcode._tcp");
    console.log(`Preview:      ${session.previewURL}`);
    console.log(`Worktree:     ${preview.worktreePath}`);
    console.log("Press Ctrl-C to stop. The isolated worktree will be preserved.\n");

    const shutdown = async () => {
      shuttingDown = true;
      process.off("SIGINT", shutdown);
      process.off("SIGTERM", shutdown);
      sessions.stopAll();
      bonjour?.stop();
      await app?.close();
    };
    process.on("SIGINT", shutdown);
    process.on("SIGTERM", shutdown);
    await new Promise<void>((resolve, reject) => {
      preview?.process.once("exit", (code, signal) => {
        if (!shuttingDown) {
          console.error(`Preview stopped (${signal ?? `status ${code ?? "unknown"}`}); Bridge remains available for inspection.`);
        }
        resolve();
      });
    });
  } catch (error) {
    preview?.process.kill("SIGTERM");
    bonjour?.stop();
    await app?.close();
    if (workspace && !ready) await removeFailedWorkspace(workspace).catch(() => undefined);
    throw error;
  }
}

main().catch((error) => {
  console.error(`TouchCode failed: ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
});
