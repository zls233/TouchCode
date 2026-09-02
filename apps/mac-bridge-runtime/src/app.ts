import Fastify from "fastify";
import { unlink, writeFile } from "node:fs/promises";
import path from "node:path";
import {
  acceptedVisualRunRequestSchema,
  deviceIdentityCapability,
  deviceIdentitySchema,
  pairSessionRequestSchema,
  touchCodeProtocolVersion,
  type AnnotationCapture,
  type AcceptedVisualRunRequest,
  type DeviceIdentity,
} from "@touchcode/protocol";
import { CodexSdkProvider } from "./coding-agents/codex-sdk-provider.js";
import { CodingAgentRegistry } from "./coding-agents/provider.js";
import { DemoRunManager } from "./demo-run-manager.js";
import { DemoSessionManager, SessionLifecycleError } from "./demo-session-manager.js";
import { ProjectGrantStore } from "./project-grants.js";

export type BridgeAppOptions = {
  grants?: ProjectGrantStore;
  codingAgents?: CodingAgentRegistry;
  bridgeBaseURL?: string;
  demoSessions?: DemoSessionManager;
  demoRuns?: DemoRunManager;
  hostIdentity?: DeviceIdentity;
};

function isLoopback(address: string) {
  return address === "127.0.0.1" || address === "::1" || address === "::ffff:127.0.0.1";
}

function sessionToken(headers: Record<string, unknown>) {
  const value = headers["x-touchcode-session-token"];
  return typeof value === "string" ? value : undefined;
}

function lifecycleFailure(error: unknown, activeOnly = false) {
  const code = error instanceof SessionLifecycleError ? error.code : "session_token_invalid";
  if (code === "session_stopped" && activeOnly) return { status: 410, body: { error: code } };
  return { status: 401, body: { error: code === "session_not_found" ? "session_unauthorized" : code } };
}

function authorizeActive(sessions: DemoSessionManager, sessionId: string, token: string | undefined) {
  const manager = sessions as DemoSessionManager & { authorizeActive?: DemoSessionManager["authorizeActive"] };
  return manager.authorizeActive
    ? manager.authorizeActive(sessionId, token)
    : sessions.authorize(sessionId, token);
}

function decodeJPEG(encoded: string) {
  const bytes = Buffer.from(encoded, "base64");
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes[2] !== 0xff) {
    throw new Error("Annotated image must be a JPEG screenshot");
  }
  return bytes;
}

export async function createBridgeApp(options: BridgeAppOptions = {}) {
  const hostIdentity = options.hostIdentity === undefined
    ? undefined
    : deviceIdentitySchema.parse(options.hostIdentity);
  // 12 MiB of JPEG data expands to roughly 16 MiB when encoded as JSON/base64.
  const app = Fastify({ logger: false, bodyLimit: 17 * 1024 * 1024 });
  const grants = options.grants ?? new ProjectGrantStore();
  const codingAgents = options.codingAgents ?? new CodingAgentRegistry();
  if (!options.codingAgents) codingAgents.register(new CodexSdkProvider());
  const sessions = options.demoSessions
    ?? new DemoSessionManager(grants, options.bridgeBaseURL ?? "http://127.0.0.1:4317");
  const runs = options.demoRuns ?? new DemoRunManager();

  app.get("/health", async () => ({
    status: "ok",
    service: "touchcode-mac-bridge",
    role: "bridge",
    version: "0.1.0",
  }));

  app.get("/v1/hello", async () => {
    const capabilities = ["pairing", "workspace", "preview", "codex"];
    if (hostIdentity) capabilities.push(deviceIdentityCapability);
    return {
      protocolVersion: touchCodeProtocolVersion,
      role: "host" as const,
      platform: "macOS" as const,
      appVersion: "0.1.0",
      capabilities,
      bridgeURL: options.bridgeBaseURL ?? "http://127.0.0.1:4317",
      ...(hostIdentity ? { identity: hostIdentity } : {}),
    };
  });

  // Kept only so the paused Mac GUI can still launch its bundled demo.
  app.post("/v1/demo-sessions", async (request, reply) => {
    if (!isLoopback(request.ip)) return reply.code(403).send({ error: "local_mac_only" });
    try {
      return reply.code(201).send(await sessions.createOrReuse());
    } catch (error) {
      return reply.code(500).send({
        error: "session_failed",
        message: error instanceof Error ? error.message : "Unable to create session",
      });
    }
  });

  const pair = async (request: { body: unknown }, reply: { code: (status: number) => { send: (body: object) => unknown } }) => {
    const parsed = pairSessionRequestSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: "invalid_pairing_code" });
    try {
      return sessions.pair(parsed.data.pairingCode);
    } catch (error) {
      return reply.code(404).send({
        error: "pairing_failed",
        message: error instanceof Error ? error.message : "Pairing failed",
      });
    }
  };
  app.post("/v1/sessions/pair", pair);
  app.post("/v1/demo-sessions/pair", pair);

  for (const prefix of ["/v1/sessions", "/v1/demo-sessions"] as const) {
    app.get<{ Params: { sessionId: string } }>(`${prefix}/:sessionId`, async (request, reply) => {
      try {
        const session = sessions.authorize(
          request.params.sessionId,
          sessionToken(request.headers),
        );
        return sessions.publicRecord(session);
      } catch (error) {
          const failure = lifecycleFailure(error);
          return reply.code(failure.status).send(failure.body);
      }
    });

    app.post<{ Params: { sessionId: string } }>(
      `${prefix}/:sessionId/heartbeat`,
      async (request, reply) => {
        try {
          return sessions.heartbeat(request.params.sessionId, sessionToken(request.headers));
        } catch (error) {
          const failure = lifecycleFailure(error);
          return reply.code(failure.status).send(failure.body);
        }
      },
    );

    const editPath = prefix === "/v1/sessions" ? "edits" : "visual-runs";
    app.post<{ Params: { sessionId: string } }>(
      `${prefix}/:sessionId/${editPath}`,
      async (request, reply) => {
        const parsed = acceptedVisualRunRequestSchema.safeParse(request.body);
        if (!parsed.success) {
          return reply.code(400).send({ error: "invalid_visual_edit", details: parsed.error.issues });
        }
        try {
          const session = authorizeActive(sessions,
            request.params.sessionId,
            sessionToken(request.headers),
          );
          const provider = codingAgents.get(parsed.data.provider);
          if (!(await provider.isAvailable())) {
            return reply.code(503).send({ error: "coding_agent_unavailable" });
          }
          const screenshots = await persistCaptures(sessions, session.sessionId, parsed.data);
          const first = screenshots[0];
          if (!first) throw new Error("At least one annotation capture is required");
          const run = runs.create(session.sessionId, {
            projectId: session.projectId,
            worktreePath: session.worktreePath,
            provider: parsed.data.provider,
            intent: {
              type: "edit.intent.v1",
              intentId: crypto.randomUUID(),
              sessionId: session.sessionId,
              selectionEventId: crypto.randomUUID(),
              instruction: instructionFor(parsed.data),
              inputMode: parsed.data.inputMode === "annotation" ? "text" : parsed.data.inputMode,
            },
            visualContext: {
              screenshotPath: first.path,
              screenshotPaths: screenshots.map((capture) => capture.path),
              viewportWidth: first.viewportWidth,
              viewportHeight: first.viewportHeight,
              ...(first.elements ? { elements: first.elements } : {}),
            },
          }, provider);
          sessions.setLatestRun(session.sessionId, run.runId);
          return reply.code(202).send(run);
        } catch (error) {
          if (error instanceof SessionLifecycleError) {
            const failure = lifecycleFailure(error, true);
            return reply.code(failure.status).send(failure.body);
          }
          return reply.code(400).send({
            error: "visual_edit_failed",
            message: error instanceof Error ? error.message : "Unable to start visual edit",
          });
        }
      },
    );

    app.get<{ Params: { sessionId: string; runId: string } }>(
      `${prefix}/:sessionId/runs/:runId`,
      async (request, reply) => {
        try {
          authorizeActive(sessions, request.params.sessionId, sessionToken(request.headers));
          return runs.forSession(request.params.sessionId, request.params.runId);
        } catch (error) {
          if (error instanceof SessionLifecycleError) {
            const failure = lifecycleFailure(error, true);
            return reply.code(failure.status).send(failure.body);
          }
          return reply.code(404).send({
            error: "unknown_coding_run",
            message: error instanceof Error ? error.message : "Unknown coding run",
          });
        }
      },
    );

    app.get<{ Params: { sessionId: string; runId: string } }>(
      `${prefix}/:sessionId/runs/:runId/events`,
      async (request, reply) => {
        try {
          authorizeActive(sessions, request.params.sessionId, sessionToken(request.headers));
          reply.hijack();
          reply.raw.writeHead(200, {
            "cache-control": "no-cache",
            connection: "keep-alive",
            "content-type": "text/event-stream",
            "x-accel-buffering": "no",
          });
          // Initial comment to flush headers through proxies.
          reply.raw.write(`: connected\n\n`);
          let eventId = 0;
          const send = (snapshot: unknown) => {
            eventId += 1;
            const payload = JSON.stringify(snapshot);
            // `id` enables Last-Event-ID reconnection; `event` keeps client filtering simple.
            reply.raw.write(`id: ${eventId}\nevent: snapshot\ndata: ${payload}\n\n`);
          };
          const unsubscribe = runs.subscribe(request.params.sessionId, request.params.runId, send);
          // Heartbeat prevents idle timeout on proxies and lets the client detect half-open connections.
          const heartbeat = setInterval(() => {
            try { reply.raw.write(`: heartbeat\n\n`); } catch {}
          }, 15000);
          const cleanup = () => {
            clearInterval(heartbeat);
            unsubscribe();
          };
          request.raw.on("close", cleanup);
          // Also handle client disconnect detection via `finish`/`error`.
          reply.raw.on("close", cleanup);
          reply.raw.on("error", cleanup);
        } catch (error) {
          if (error instanceof SessionLifecycleError) {
            const failure = lifecycleFailure(error, true);
            return reply.code(failure.status).send(failure.body);
          }
          return reply.code(404).send({
            error: "unknown_coding_run",
            message: error instanceof Error ? error.message : "Unknown coding run",
          });
        }
      },
    );

    for (const action of ["keep", "undo"] as const) {
      app.post<{ Params: { sessionId: string; runId: string } }>(
        `${prefix}/:sessionId/runs/:runId/${action}`,
        async (request, reply) => {
          try {
            authorizeActive(sessions, request.params.sessionId, sessionToken(request.headers));
            const snapshot = await runs.decide(request.params.sessionId, request.params.runId, action);
            return snapshot;
          } catch (error) {
            if (error instanceof SessionLifecycleError) {
              const failure = lifecycleFailure(error, true);
              return reply.code(failure.status).send(failure.body);
            }
            const message = error instanceof Error ? error.message : "Unknown coding run";
            const code = message.includes("already decided") ? 409 : 404;
            return reply.code(code).send({
              error: code === 409 ? "already_decided" : "unknown_coding_run",
              message,
            });
          }
        },
      );
    }
  }

  return app;
}

function instructionFor(request: AcceptedVisualRunRequest) {
  if ("captures" in request) {
    return request.instruction ?? "Interpret the Apple Pencil annotations and make the smallest unambiguous change. If the intended change is unclear, ask one clarification question and do not modify files.";
  }
  return request.instruction;
}

async function persistCaptures(
  sessions: DemoSessionManager,
  sessionId: string,
  request: AcceptedVisualRunRequest,
) {
  const rawCaptures: Array<{
    image: string;
    viewportWidth: number;
    viewportHeight: number;
    elements?: AnnotationCapture["elements"];
  }> = "captures" in request
    ? request.captures.map((capture) => ({
      image: capture.annotatedImageBase64,
      viewportWidth: capture.viewport.width,
      viewportHeight: capture.viewport.height,
      elements: capture.elements,
    }))
    : [{
      image: request.annotatedImageBase64,
      viewportWidth: request.viewportWidth,
      viewportHeight: request.viewportHeight,
    }];
  const totalBytes = rawCaptures.reduce((total, capture) => total + Buffer.byteLength(capture.image, "base64"), 0);
  if (totalBytes > 12 * 1024 * 1024) throw new Error("Annotation captures exceed the 12 MiB request limit");
  const inputDirectory = await sessions.inputDirectory(sessionId);
  const written: string[] = [];
  try {
    const persisted = [];
    for (const capture of rawCaptures) {
      const pathName = path.join(inputDirectory, `${crypto.randomUUID()}.jpg`);
      await writeFile(pathName, decodeJPEG(capture.image), { flag: "wx" });
      written.push(pathName);
      persisted.push({
        path: pathName,
        viewportWidth: capture.viewportWidth,
        viewportHeight: capture.viewportHeight,
        ...(capture.elements ? { elements: capture.elements } : {}),
      });
    }
    return persisted;
  } catch (error) {
    await Promise.all(written.map((filePath) => unlink(filePath).catch(() => undefined)));
    throw error;
  }
}
