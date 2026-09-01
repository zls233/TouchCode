import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { EventEmitter } from "node:events";
import { promisify } from "node:util";
import test from "node:test";
import { createBridgeApp } from "../src/app.js";
import { CodingAgentRegistry, type CodingAgentProvider } from "../src/coding-agents/provider.js";
import { DemoSessionManager } from "../src/demo-session-manager.js";
import { ProjectGrantStore } from "../src/project-grants.js";
import { prepareWorkspace, removeFailedWorkspace } from "../src/project-workspace.js";

const execFileAsync = promisify(execFile);
async function git(cwd: string, ...args: string[]) { return execFileAsync("git", args, { cwd, encoding: "utf8" }); }

class FakePreview extends EventEmitter {
  exitCode: number | null = null;
  signalCode: NodeJS.Signals | null = null;
  kill() { this.exitCode = 0; this.emit("exit", 0, null); }
}

test("CLI closed loop (mock preview): worktree + pairing + V2 run", async () => {
  const worktree = await mkdtemp(path.join(tmpdir(), "touchcode-cli-closed-worktree-"));
  // Use non-Git worktree for fast checkpoint (returns null) to verify closed loop without Git overhead
  await writeFile(path.join(worktree, "index.html"), "<h1>hello</h1>");

  const fakePreview = new FakePreview() as unknown as import("node:child_process").ChildProcess;
  (fakePreview as unknown as { exitCode: null }).exitCode = null;

  const grants = new ProjectGrantStore();
  const sessions = new DemoSessionManager(grants, "http://127.0.0.1:4317");
  const previewPort = 5173;
  const session = await sessions.registerProjectSession({
    worktreePath: worktree,
    previewURL: `http://127.0.0.1:${previewPort}`,
    port: previewPort,
    process: fakePreview,
  });
  // Mock workspace for cleanup compatibility
  const workspace = { sourceRoot: worktree, worktreePath: worktree, commandCwd: worktree } as unknown as Awaited<ReturnType<typeof prepareWorkspace>>;

  assert.match(session.pairingCode, /^\d{6}$/);
  const paired = sessions.pair(session.pairingCode);
  assert.equal(paired.sessionId, session.sessionId);

  let providerCalled = false;
  const provider: CodingAgentProvider = {
    kind: "codex",
    async isAvailable() { return true; },
    async run(req) {
      providerCalled = true;
      return { runId: "r", provider: "codex", status: "succeeded", outcome: "applied", clarificationQuestion: null, summary: "cli" };
    },
  };
  const agents = new CodingAgentRegistry(); agents.register(provider);
  const app = await createBridgeApp({ grants, codingAgents: agents, bridgeBaseURL: "http://127.0.0.1:4317", demoSessions: sessions });

  const jpeg = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(100)]).toString("base64");
  const cap = { annotatedImageBase64: jpeg, viewport: { url: `http://127.0.0.1:${previewPort}`, width: 1024, height: 768, scrollX: 0, scrollY: 0, zoomScale: 1, devicePixelRatio: 2 }, annotationBounds: { x: 0, y: 0, width: 10, height: 10 }, elements: [] };
  const res = await app.inject({
    method: "POST",
    url: `/v1/sessions/${session.sessionId}/edits`,
    headers: { "x-touchcode-session-token": paired.clientToken },
    payload: { type: "visual.run.v2", draftId: "d1", inputMode: "text", instruction: "make it blue", captures: [cap] },
  });
  assert.equal(res.statusCode, 202);
  const { runId } = res.json();
  let final: { statusCode: number; json: () => { status: string; previewRevision?: string; summary?: string } } | undefined;
  for (let i = 0; i < 30; i++) {
    await new Promise((r) => setTimeout(r, 100));
    const poll = await app.inject({ method: "GET", url: `/v1/sessions/${session.sessionId}/runs/${runId}`, headers: { "x-touchcode-session-token": paired.clientToken } });
    if (poll.statusCode === 200 && (poll.json() as { status: string }).status === "succeeded") { final = poll as unknown as typeof final; break; }
  }
  assert.ok(final, "run should reach succeeded");
  assert.equal(final!.statusCode, 200);
  assert.equal(final!.json().status, "succeeded");
  assert.match(final!.json().previewRevision ?? "", /^\d+$/);

  // A valid token can inspect a stopped session, while active operations are rejected.
  fakePreview.emit("exit", 0, null);
  const stopped = await app.inject({
    method: "GET",
    url: `/v1/sessions/${session.sessionId}`,
    headers: { "x-touchcode-session-token": paired.clientToken },
  });
  assert.equal(stopped.statusCode, 200);
  assert.equal(stopped.json().status, "stopped");
  const wrongToken = await app.inject({
    method: "GET",
    url: `/v1/sessions/${session.sessionId}`,
    headers: { "x-touchcode-session-token": "wrong-token" },
  });
  assert.equal(wrongToken.statusCode, 401);
  const stoppedEdit = await app.inject({
    method: "POST",
    url: `/v1/sessions/${session.sessionId}/edits`,
    headers: { "x-touchcode-session-token": paired.clientToken },
    payload: { type: "visual.run.v2", draftId: "stopped", inputMode: "text", instruction: "make it blue", captures: [cap] },
  });
  assert.equal(stoppedEdit.statusCode, 410);
  assert.equal(stoppedEdit.json().error, "session_stopped");

  await app.close();
  await execFileAsync("rm", ["-rf", worktree]).catch(() => undefined);
});
