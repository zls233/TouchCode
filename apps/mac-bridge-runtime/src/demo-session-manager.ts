import { appendFile, cp, mkdir, readFile, readlink, symlink } from "node:fs/promises";
import { execFile } from "node:child_process";
import { randomBytes, timingSafeEqual } from "node:crypto";
import { homedir, networkInterfaces } from "node:os";
import path from "node:path";
import net from "node:net";
import { fileURLToPath } from "node:url";
import { spawn, type ChildProcess } from "node:child_process";
import { promisify } from "node:util";
import type { ProjectGrantStore } from "./project-grants.js";

const execFileAsync = promisify(execFile);
const moduleDirectory = path.dirname(fileURLToPath(import.meta.url));
const workspaceRoot = path.resolve(moduleDirectory, "../../..");
const demoTemplatePath = path.join(workspaceRoot, "packages/demo-web");
const sessionsRoot = path.join(workspaceRoot, ".touchcode/sessions");

export type SessionStatus = "starting" | "running" | "stopped";

export class SessionLifecycleError extends Error {
  constructor(readonly code: "session_not_found" | "session_token_invalid" | "session_stopped") {
    super(code);
    this.name = "SessionLifecycleError";
  }
}

export type WorkspaceSessionRecord = {
  sessionId: string;
  previewURL: string;
  bridgeURL: string;
  pairingCode: string;
  ipadConnected: boolean;
  latestRunId: string | null;
  errorMessage: string | null;
  status: SessionStatus;
};

type ManagedSession = WorkspaceSessionRecord & {
  projectId: string;
  worktreePath: string;
  port: number;
  status: SessionStatus;
  process: ChildProcess;
  clientToken: string;
  lastHeartbeatAt: number | null;
};

async function availablePort() {
  return await new Promise<number>((resolve, reject) => {
    const server = net.createServer();
    server.once("error", reject);
    server.listen(0, "0.0.0.0", () => {
      const address = server.address();
      if (!address || typeof address === "string") {
        server.close();
        reject(new Error("Unable to allocate preview port"));
        return;
      }
      const port = address.port;
      server.close((error) => error ? reject(error) : resolve(port));
    });
  });
}

async function waitForPreview(port: number, child: ChildProcess) {
  for (let attempt = 0; attempt < 300; attempt += 1) {
    if (child.exitCode !== null) throw new Error("The demo preview stopped before it became ready");
    const connected = await new Promise<boolean>((resolve) => {
      const socket = net.createConnection({ host: "127.0.0.1", port });
      socket.once("connect", () => {
        socket.destroy();
        resolve(true);
      });
      socket.once("error", () => resolve(false));
    });
    if (connected) return;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error("The demo preview did not become ready in time");
}

export function localIPv4Address() {
  const interfaces = networkInterfaces();
  const preferred = ["en0", "en1"];
  for (const name of [...preferred, ...Object.keys(interfaces)]) {
    const addresses = interfaces[name] ?? [];
    const address = addresses.find((item) => item.family === "IPv4" && !item.internal);
    if (address) return address.address;
  }
  return "127.0.0.1";
}

async function linkTemplateDependencies(sessionPath: string) {
  const templateModules = path.join(demoTemplatePath, "node_modules");
  const sessionModules = path.join(sessionPath, "node_modules");
  const resolvedTemplateModules = await readlink(templateModules).catch(() => templateModules);
  const target = path.isAbsolute(resolvedTemplateModules)
    ? resolvedTemplateModules
    : path.resolve(demoTemplatePath, resolvedTemplateModules);
  await symlink(target, sessionModules, "dir");
}

async function initializeGitRepository(sessionPath: string) {
  await execFileAsync("git", ["init", "--quiet"], { cwd: sessionPath });
  await appendFile(path.join(sessionPath, ".git/info/exclude"), "\n.touchcode-inputs/\n");
  await execFileAsync("git", ["add", "."], { cwd: sessionPath });
  await execFileAsync("git", [
    "-c", "user.name=TouchCode",
    "-c", "user.email=touchcode@local",
    "commit", "--quiet", "-m", "TouchCode demo baseline",
  ], { cwd: sessionPath });
}

function randomPairingCode() {
  return String(Math.floor(100_000 + Math.random() * 900_000));
}

function tokensMatch(expected: string, actual: string) {
  const expectedBytes = Buffer.from(expected);
  const actualBytes = Buffer.from(actual);
  return expectedBytes.length === actualBytes.length && timingSafeEqual(expectedBytes, actualBytes);
}

export class DemoSessionManager {
  readonly #sessions = new Map<string, ManagedSession>();

  constructor(
    private readonly grants: ProjectGrantStore,
    private readonly bridgeBaseURL: string,
    private readonly inputsRoot = path.join(
      homedir(),
      "Library",
      "Application Support",
      "TouchCode",
      "sessions",
    ),
  ) {}

  async createOrReuse() {
    const active = Array.from(this.#sessions.values()).find(
      (session) => session.status === "running" && session.process.exitCode === null,
    );
    return active ? this.publicRecord(active) : this.create();
  }

  async create() {
    // Hydrate cloud-backed workspace metadata before Vite synchronously hashes it.
    await readFile(path.join(workspaceRoot, "pnpm-lock.yaml"));
    await mkdir(sessionsRoot, { recursive: true });
    const sessionId = crypto.randomUUID();
    const sessionPath = path.join(sessionsRoot, sessionId);
    await cp(demoTemplatePath, sessionPath, {
      recursive: true,
      filter: (source) => {
        const relative = path.relative(demoTemplatePath, source);
        return relative !== "node_modules" && !relative.startsWith(`node_modules${path.sep}`)
          && relative !== "dist" && !relative.startsWith(`dist${path.sep}`);
      },
    });
    await linkTemplateDependencies(sessionPath);
    await initializeGitRepository(sessionPath);

    const port = await availablePort();
    const viteExecutable = path.join(demoTemplatePath, "node_modules/.bin/vite");
    const child = spawn(viteExecutable, ["--host", "0.0.0.0", "--port", String(port)], {
      cwd: sessionPath,
      env: { ...process.env, TOUCHCODE_SESSION_ID: sessionId },
      stdio: ["ignore", "pipe", "pipe"],
    });
    const grant = await this.grants.grant(sessionPath);
    const previewURL = `http://${localIPv4Address()}:${port}`;
    const record: ManagedSession = {
      sessionId,
      projectId: grant.id,
      worktreePath: grant.canonicalRoot,
      previewURL,
      bridgeURL: this.bridgeBaseURL,
      port,
      status: "starting",
      pairingCode: this.uniquePairingCode(),
      ipadConnected: false,
      latestRunId: null,
      errorMessage: null,
      clientToken: randomBytes(32).toString("hex"),
      lastHeartbeatAt: null,
      process: child,
    };
    this.#sessions.set(sessionId, record);

    child.stdout?.on("data", () => { record.status = "running"; });
    child.stderr?.on("data", (chunk: Buffer) => {
      record.errorMessage = chunk.toString("utf8").trim().slice(-2_000) || record.errorMessage;
    });
    child.once("exit", (code, signal) => {
      record.status = "stopped";
      record.errorMessage = record.errorMessage
        ?? `Preview exited (${signal ? `signal ${signal}` : `status ${code ?? "unknown"}`})`;
    });
    try {
      await waitForPreview(port, child);
      record.status = "running";
    } catch (error) {
      child.kill();
      this.#sessions.delete(sessionId);
      throw error;
    }
    return this.publicRecord(record);
  }

  async registerProjectSession(input: {
    worktreePath: string;
    previewURL: string;
    port: number;
    process: ChildProcess;
  }) {
    const grant = await this.grants.grant(input.worktreePath);
    const sessionId = crypto.randomUUID();
    const record: ManagedSession = {
      sessionId,
      projectId: grant.id,
      worktreePath: grant.canonicalRoot,
      previewURL: input.previewURL,
      bridgeURL: this.bridgeBaseURL,
      port: input.port,
      status: "running",
      pairingCode: this.uniquePairingCode(),
      ipadConnected: false,
      latestRunId: null,
      errorMessage: null,
      clientToken: randomBytes(32).toString("hex"),
      lastHeartbeatAt: null,
      process: input.process,
    };
    this.#sessions.set(sessionId, record);
    input.process.once("exit", (code, signal) => {
      record.status = "stopped";
      record.errorMessage = `Preview exited (${signal ? `signal ${signal}` : `status ${code ?? "unknown"}`})`;
    });
    return this.publicRecord(record);
  }

  get(sessionId: string) {
    const record = this.#sessions.get(sessionId);
    if (!record) throw new SessionLifecycleError("session_not_found");
    return record;
  }

  async inputDirectory(sessionId: string) {
    this.get(sessionId);
    const directory = path.join(this.inputsRoot, sessionId, "inputs");
    await mkdir(directory, { recursive: true });
    return directory;
  }

  pair(pairingCode: string) {
    const record = Array.from(this.#sessions.values()).find(
      (session) => session.pairingCode === pairingCode
        && session.status === "running"
        && session.process.exitCode === null,
    );
    if (!record) throw new Error("Pairing code is invalid or expired");
    record.lastHeartbeatAt = Date.now();
    record.ipadConnected = true;
    return { ...this.publicRecord(record), clientToken: record.clientToken };
  }

  authorize(sessionId: string, token: string | undefined) {
    const record = this.#sessions.get(sessionId);
    if (!record) throw new SessionLifecycleError("session_not_found");
    if (!token || !tokensMatch(record.clientToken, token)) throw new SessionLifecycleError("session_token_invalid");
    if (record.status === "running" && record.process.exitCode !== null) record.status = "stopped";
    record.lastHeartbeatAt = Date.now();
    record.ipadConnected = true;
    return record;
  }

  authorizeActive(sessionId: string, token: string | undefined) {
    const record = this.authorize(sessionId, token);
    if (record.status !== "running") throw new SessionLifecycleError("session_stopped");
    return record;
  }

  heartbeat(sessionId: string, token: string | undefined) {
    return this.publicRecord(this.authorize(sessionId, token));
  }

  setLatestRun(sessionId: string, runId: string) {
    const record = this.get(sessionId);
    record.latestRunId = runId;
  }

  private uniquePairingCode() {
    for (let attempt = 0; attempt < 20; attempt += 1) {
      const code = randomPairingCode();
      if (!Array.from(this.#sessions.values()).some((session) => session.pairingCode === code)) {
        return code;
      }
    }
    throw new Error("Unable to allocate a pairing code");
  }

  stopAll() {
    for (const session of this.#sessions.values()) {
      if (session.process.exitCode === null) session.process.kill("SIGTERM");
    }
  }

  publicRecord(record: ManagedSession): WorkspaceSessionRecord {
    const ipadConnected = record.lastHeartbeatAt !== null
      && Date.now() - record.lastHeartbeatAt < 15_000;
    record.ipadConnected = ipadConnected;
    return {
      sessionId: record.sessionId,
      previewURL: record.previewURL,
      bridgeURL: record.bridgeURL,
      pairingCode: record.pairingCode,
      ipadConnected,
      latestRunId: record.latestRunId,
      errorMessage: record.errorMessage,
      status: record.status,
    };
  }
}
