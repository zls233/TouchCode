import Fastify from "fastify";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import {
  codingRunRequestSchema,
  demoCodingRunRequestSchema,
  elementSelectionSchema,
  projectGrantRequestSchema,
  visualCodingRunRequestSchema,
} from "@touchcode/protocol";
import { BridgeState } from "./bridge-state.js";
import { CodexSdkProvider } from "./coding-agents/codex-sdk-provider.js";
import { CodingAgentRegistry } from "./coding-agents/provider.js";
import { ProjectGrantStore } from "./project-grants.js";
import { DemoSessionManager } from "./demo-session-manager.js";

export type BridgeAppOptions = {
  grants?: ProjectGrantStore;
  state?: BridgeState;
  codingAgents?: CodingAgentRegistry;
  bridgeBaseURL?: string;
  demoSessions?: DemoSessionManager;
};

export async function createBridgeApp(options: BridgeAppOptions = {}) {
  const app = Fastify({ logger: false, bodyLimit: 8_500_000 });
  const grants = options.grants ?? new ProjectGrantStore();
  const state = options.state ?? new BridgeState();
  const codingAgents = options.codingAgents ?? new CodingAgentRegistry();
  if (!options.codingAgents) codingAgents.register(new CodexSdkProvider());
  const demoSessions = options.demoSessions
    ?? new DemoSessionManager(grants, options.bridgeBaseURL ?? "http://127.0.0.1:4317");

  app.get("/health", async () => ({
    status: "ok",
    service: "touchcode-mac-bridge",
    role: "bridge",
    version: "0.1.0",
  }));

  app.post("/v1/projects/grants", async (request, reply) => {
    const parsed = projectGrantRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "invalid_request", details: parsed.error.issues });
    }
    try {
      return await grants.grant(parsed.data.path);
    } catch (error) {
      return reply.code(400).send({
        error: "invalid_project",
        message: error instanceof Error ? error.message : "Unknown error",
      });
    }
  });

  app.post("/v1/selections", async (request, reply) => {
    const parsed = elementSelectionSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "invalid_selection", details: parsed.error.issues });
    }
    const result = state.acceptSelection(parsed.data);
    return reply.code(result.duplicate ? 200 : 202).send(result);
  });

  app.get("/v1/selections", async () => ({ items: state.listSelections() }));

  app.post("/v1/demo-sessions", async (_request, reply) => {
    try {
      return reply.code(201).send(await demoSessions.createOrReuse());
    } catch (error) {
      return reply.code(500).send({
        error: "demo_session_failed",
        message: error instanceof Error ? error.message : "Unknown error",
      });
    }
  });

  app.get<{ Params: { sessionId: string } }>("/v1/demo-sessions/:sessionId", async (request, reply) => {
    try {
      return demoSessions.publicRecord(demoSessions.get(request.params.sessionId));
    } catch (error) {
      return reply.code(404).send({
        error: "unknown_demo_session",
        message: error instanceof Error ? error.message : "Unknown error",
      });
    }
  });

  app.post<{ Params: { sessionId: string } }>("/v1/demo-sessions/:sessionId/runs", async (request, reply) => {
    const parsed = demoCodingRunRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "invalid_coding_run", details: parsed.error.issues });
    }
    try {
      const session = demoSessions.get(request.params.sessionId);
      if (parsed.data.intent.sessionId !== session.sessionId
        || parsed.data.selection.sessionId !== session.sessionId
        || parsed.data.intent.selectionEventId !== parsed.data.selection.eventId) {
        return reply.code(409).send({ error: "session_context_mismatch" });
      }
      const provider = codingAgents.get(parsed.data.provider);
      return await provider.run({
        projectId: session.projectId,
        worktreePath: session.worktreePath,
        provider: parsed.data.provider,
        intent: parsed.data.intent,
        selection: parsed.data.selection,
      });
    } catch (error) {
      return reply.code(400).send({
        error: "coding_run_failed",
        message: error instanceof Error ? error.message : "Unknown error",
      });
    }
  });

  app.post<{ Params: { sessionId: string } }>("/v1/demo-sessions/:sessionId/visual-runs", async (request, reply) => {
    const parsed = visualCodingRunRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "invalid_visual_run", details: parsed.error.issues });
    }

    try {
      const session = demoSessions.get(request.params.sessionId);
      const captureId = crypto.randomUUID();
      const inputDirectory = path.join(session.worktreePath, ".touchcode-inputs");
      const screenshotPath = path.join(inputDirectory, `${captureId}.jpg`);
      await mkdir(inputDirectory, { recursive: true });
      await writeFile(screenshotPath, Buffer.from(parsed.data.annotatedImageBase64, "base64"));

      const provider = codingAgents.get(parsed.data.provider);
      if (!(await provider.isAvailable())) {
        return reply.code(503).send({ error: "coding_agent_unavailable" });
      }
      return await provider.run({
        projectId: session.projectId,
        worktreePath: session.worktreePath,
        provider: parsed.data.provider,
        intent: {
          type: "edit.intent.v1",
          intentId: crypto.randomUUID(),
          sessionId: session.sessionId,
          selectionEventId: captureId,
          instruction: parsed.data.instruction,
          inputMode: parsed.data.inputMode,
          screenshotPath,
        },
        visualContext: {
          screenshotPath,
          viewportWidth: parsed.data.viewportWidth,
          viewportHeight: parsed.data.viewportHeight,
          elements: parsed.data.elements,
        },
      });
    } catch (error) {
      return reply.code(400).send({
        error: "visual_run_failed",
        message: error instanceof Error ? error.message : "Unknown error",
      });
    }
  });

  app.post("/v1/coding-runs", async (request, reply) => {
    const parsed = codingRunRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "invalid_coding_run", details: parsed.error.issues });
    }

    try {
      const grantedRoot = grants.getRoot(parsed.data.projectId);
      if (grantedRoot !== parsed.data.worktreePath) {
        return reply.code(403).send({ error: "worktree_not_granted" });
      }
      const provider = codingAgents.get(parsed.data.provider);
      if (!(await provider.isAvailable())) {
        return reply.code(503).send({ error: "coding_agent_unavailable" });
      }
      return await provider.run(parsed.data);
    } catch (error) {
      return reply.code(400).send({
        error: "coding_run_failed",
        message: error instanceof Error ? error.message : "Unknown error",
      });
    }
  });

  return app;
}
