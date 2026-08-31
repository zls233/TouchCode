import assert from "node:assert/strict";
import { mkdtemp, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { pairedWorkspaceSessionSchema, type CodingRunRequest } from "@touchcode/protocol";
import { createBridgeApp } from "../src/app.js";
import { CodingAgentRegistry, type CodingAgentProvider } from "../src/coding-agents/provider.js";
import type { DemoSessionManager } from "../src/demo-session-manager.js";

test("identifies itself as a bridge rather than a coding agent", async () => {
  const app = await createBridgeApp();
  const response = await app.inject({ method: "GET", url: "/health" });
  assert.equal(response.statusCode, 200);
  assert.deepEqual(response.json(), {
    status: "ok",
    service: "touchcode-mac-bridge",
    role: "bridge",
    version: "0.1.0",
  });
  await app.close();
});

test("keeps session creation on the local Mac", async () => {
  const app = await createBridgeApp();
  const response = await app.inject({
    method: "POST",
    url: "/v1/demo-sessions",
    remoteAddress: "192.168.1.20",
  });
  assert.equal(response.statusCode, 403);
  assert.equal(response.json().error, "local_mac_only");
  await app.close();
});

test("does not pair an unknown code", async () => {
  const app = await createBridgeApp();
  const response = await app.inject({
    method: "POST",
    url: "/v1/demo-sessions/pair",
    payload: { pairingCode: "123456" },
  });
  assert.equal(response.statusCode, 404);
  assert.equal(response.json().error, "pairing_failed");
  await app.close();
});

test("pairs an iPad through the sessions endpoint and returns its session credentials", async () => {
  let pairedCode: string | undefined;
  const fakeSessions = {
    pair(pairingCode: string) {
      pairedCode = pairingCode;
      return {
        sessionId: "session-1",
        previewURL: "http://127.0.0.1:5173",
        bridgeURL: "http://127.0.0.1:4317",
        pairingCode,
        ipadConnected: true,
        latestRunId: null,
        errorMessage: null,
        clientToken: "client-token-1",
      };
    },
  } as unknown as DemoSessionManager;
  const app = await createBridgeApp({ demoSessions: fakeSessions });

  const response = await app.inject({
    method: "POST",
    url: "/v1/sessions/pair",
    payload: { pairingCode: "654321" },
  });

  assert.equal(response.statusCode, 200);
  const session = pairedWorkspaceSessionSchema.parse(response.json());
  assert.equal(pairedCode, "654321");
  assert.equal(session.sessionId, "session-1");
  assert.equal(session.clientToken, "client-token-1");
  assert.equal(session.ipadConnected, true);
  assert.equal(session.latestRunId, null);
  await app.close();
});

test("completes the iPad session handshake over local loopback HTTP", async () => {
  let paired = false;
  const session = {
    sessionId: "loopback-session",
    previewURL: "http://127.0.0.1:5173",
    bridgeURL: "http://127.0.0.1:4317",
    pairingCode: "246810",
    ipadConnected: false,
    latestRunId: null,
    errorMessage: null,
    clientToken: "loopback-client-token",
  };
  const fakeSessions = {
    async createOrReuse() {
      return { ...session };
    },
    pair(pairingCode: string) {
      if (pairingCode !== session.pairingCode) throw new Error("Pairing code is invalid or expired");
      paired = true;
      return { ...session, ipadConnected: true, clientToken: session.clientToken };
    },
    authorize(sessionId: string, token: string | undefined) {
      if (!paired || sessionId !== session.sessionId || token !== session.clientToken) {
        throw new Error("Session token is invalid");
      }
      return session;
    },
    publicRecord(record: typeof session) {
      return { ...record, clientToken: undefined };
    },
    heartbeat(sessionId: string, token: string | undefined) {
      this.authorize(sessionId, token);
      return { ...session, ipadConnected: true };
    },
  } as unknown as DemoSessionManager;
  const app = await createBridgeApp({ demoSessions: fakeSessions });
  const address = await app.listen({ host: "127.0.0.1", port: 0 });
  const baseURL = address.replace(/\/$/, "");

  try {
    const createdResponse = await fetch(`${baseURL}/v1/demo-sessions`, { method: "POST" });
    assert.equal(createdResponse.status, 201);
    assert.equal((await createdResponse.json()).sessionId, session.sessionId);

    const pairResponse = await fetch(`${baseURL}/v1/sessions/pair`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ pairingCode: session.pairingCode }),
    });
    assert.equal(pairResponse.status, 200);
    const pairedSession = pairedWorkspaceSessionSchema.parse(await pairResponse.json());
    assert.equal(pairedSession.clientToken, session.clientToken);
    assert.equal(pairedSession.ipadConnected, true);

    const sessionResponse = await fetch(`${baseURL}/v1/sessions/${session.sessionId}`, {
      headers: { "x-touchcode-session-token": pairedSession.clientToken },
    });
    assert.equal(sessionResponse.status, 200);
    assert.equal((await sessionResponse.json()).sessionId, session.sessionId);

    const heartbeatResponse = await fetch(`${baseURL}/v1/sessions/${session.sessionId}/heartbeat`, {
      method: "POST",
      headers: { "x-touchcode-session-token": pairedSession.clientToken },
    });
    assert.equal(heartbeatResponse.status, 200);
    assert.equal((await heartbeatResponse.json()).ipadConnected, true);
  } finally {
    await app.close();
  }
});

test("accepts one annotated JPEG plus a transcribed instruction without DOM context", async () => {
  const inputDirectory = await mkdtemp(path.join(tmpdir(), "touchcode-input-"));
  let received: CodingRunRequest | undefined;
  const provider: CodingAgentProvider = {
    kind: "codex",
    async isAvailable() { return true; },
    async run(request) {
      received = request;
      return {
        runId: "provider-run",
        provider: "codex",
        status: "succeeded",
        summary: "Changed the marked heading",
        outcome: "applied",
        clarificationQuestion: null,
      };
    },
  };
  const agents = new CodingAgentRegistry();
  agents.register(provider);
  let latestRunId: string | undefined;
  const managedSession = {
    sessionId: "session-1",
    projectId: "project-1",
    worktreePath: "/tmp/touchcode-worktree",
  };
  const fakeSessions = {
    authorize(sessionId: string, token: string | undefined) {
      if (sessionId !== "session-1" || token !== "secret-token") throw new Error("unauthorized");
      return managedSession;
    },
    async inputDirectory() { return inputDirectory; },
    setLatestRun(_sessionId: string, runId: string) { latestRunId = runId; },
  } as unknown as DemoSessionManager;
  const app = await createBridgeApp({ codingAgents: agents, demoSessions: fakeSessions });
  const jpeg = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(100)]);
  const response = await app.inject({
    method: "POST",
    url: "/v1/sessions/session-1/edits",
    headers: { "x-touchcode-session-token": "secret-token" },
    payload: {
      instruction: "把圈出的标题改成蓝色",
      inputMode: "voice",
      annotatedImageBase64: jpeg.toString("base64"),
      viewportWidth: 1024,
      viewportHeight: 768,
      provider: "codex",
    },
  });

  assert.equal(response.statusCode, 202);
  assert.equal(response.json().runId, latestRunId);
  for (let i = 0; i < 20 && !received; i++) await new Promise((r) => setTimeout(r, 10));
  assert.equal(received?.intent.instruction, "把圈出的标题改成蓝色");
  assert.equal(received?.intent.inputMode, "voice");
  assert.equal("elements" in (received?.visualContext ?? {}), false);
  const stored = await readFile(received!.visualContext.screenshotPath);
  assert.deepEqual(stored, jpeg);
  await app.close();
});

test("accepts an annotation-only V2 draft and persists every viewport capture", async () => {
  const inputDirectory = await mkdtemp(path.join(tmpdir(), "touchcode-v2-input-"));
  let received: CodingRunRequest | undefined;
  const provider: CodingAgentProvider = {
    kind: "codex", async isAvailable() { return true; },
    async run(request) {
      received = request;
      return { runId: "provider-run", provider: "codex", status: "succeeded", outcome: "needs_clarification", clarificationQuestion: "Which color should this use?", summary: "Need a color." };
    },
  };
  const agents = new CodingAgentRegistry(); agents.register(provider);
  const fakeSessions = {
    authorize() { return { sessionId: "session-v2", projectId: "project-1", worktreePath: "/tmp/touchcode-worktree" }; },
    async inputDirectory() { return inputDirectory; }, setLatestRun() {},
  } as unknown as DemoSessionManager;
  const app = await createBridgeApp({ codingAgents: agents, demoSessions: fakeSessions });
  const jpeg = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(100)]).toString("base64");
  const capture = { annotatedImageBase64: jpeg, viewport: { url: "http://127.0.0.1:5173", width: 1024, height: 768, scrollX: 0, scrollY: 0, zoomScale: 1, devicePixelRatio: 2 }, annotationBounds: { x: 1, y: 2, width: 3, height: 4 }, elements: [] };
  const response = await app.inject({ method: "POST", url: "/v1/sessions/session-v2/edits", payload: { type: "visual.run.v2", draftId: "draft-v2", inputMode: "annotation", captures: [capture, capture] } });
  assert.equal(response.statusCode, 202);
  for (let i = 0; i < 20 && !received; i++) await new Promise((r) => setTimeout(r, 10));
  assert.equal(received?.visualContext?.screenshotPaths?.length, 2);
  assert.match(received?.intent.instruction ?? "", /If the intended change is unclear/);
  await app.close();
});
