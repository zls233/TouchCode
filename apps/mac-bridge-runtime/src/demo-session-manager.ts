import { cp, mkdir, readlink, symlink } from "node:fs/promises";
import { execFile } from "node:child_process";
import { networkInterfaces } from "node:os";
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

export type DemoSessionRecord = {
  sessionId: string;
  projectId: string;
  worktreePath: string;
  previewURL: string;
  bridgeURL: string;
  port: number;
  status: "starting" | "running" | "stopped";
};

type ManagedSession = DemoSessionRecord & { process: ChildProcess };

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
  for (let attempt = 0; attempt < 50; attempt += 1) {
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
  await execFileAsync("git", ["add", "."], { cwd: sessionPath });
  await execFileAsync("git", [
    "-c", "user.name=TouchCode",
    "-c", "user.email=touchcode@local",
    "commit", "--quiet", "-m", "TouchCode demo baseline",
  ], { cwd: sessionPath });
}

export class DemoSessionManager {
  readonly #sessions = new Map<string, ManagedSession>();

  constructor(
    private readonly grants: ProjectGrantStore,
    private readonly bridgeBaseURL: string,
  ) {}

  async createOrReuse() {
    const active = Array.from(this.#sessions.values()).find(
      (session) => session.status === "running" && session.process.exitCode === null,
    );
    return active ? this.publicRecord(active) : this.create();
  }

  async create() {
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
      process: child,
    };
    this.#sessions.set(sessionId, record);

    child.stdout?.on("data", () => { record.status = "running"; });
    child.once("exit", () => { record.status = "stopped"; });
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

  get(sessionId: string) {
    const record = this.#sessions.get(sessionId);
    if (!record) throw new Error("Unknown demo session");
    return record;
  }

  publicRecord(record: ManagedSession): DemoSessionRecord {
    return {
      sessionId: record.sessionId,
      projectId: record.projectId,
      worktreePath: record.worktreePath,
      previewURL: record.previewURL,
      bridgeURL: record.bridgeURL,
      port: record.port,
      status: record.status,
    };
  }
}
