import { execFile } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { access, lstat, mkdir, realpath, symlink } from "node:fs/promises";
import { homedir } from "node:os";
import path from "node:path";
import net from "node:net";
import { spawn, type ChildProcess } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

export type PreparedWorkspace = {
  sourceRoot: string;
  worktreePath: string;
  commandCwd: string;
};

export type RunningPreview = PreparedWorkspace & {
  process: ChildProcess;
  port: number;
};

function within(root: string, candidate: string) {
  const relative = path.relative(root, candidate);
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}

async function git(cwd: string, args: string[]) {
  const result = await execFileAsync("git", args, { cwd, encoding: "utf8" });
  return result.stdout.trim();
}

async function pathExists(candidate: string) {
  return access(candidate).then(() => true, () => false);
}

async function linkDependencies(source: string, destination: string) {
  if (!(await pathExists(source)) || await pathExists(destination)) return;
  const info = await lstat(source);
  if (!info.isDirectory() && !info.isSymbolicLink()) return;
  const canonical = await realpath(source);
  await symlink(canonical, destination, "dir");
}

export async function prepareWorkspace(input: {
  projectPath: string;
  projectCwd: string;
  worktreesRoot?: string;
}): Promise<PreparedWorkspace> {
  const sourceRoot = await realpath(input.projectPath);
  const gitRoot = await realpath(await git(sourceRoot, ["rev-parse", "--show-toplevel"]));
  if (gitRoot !== sourceRoot) {
    throw new Error(`--project must point to the Git repository root: ${gitRoot}`);
  }

  const status = await git(sourceRoot, ["status", "--porcelain=v1", "--untracked-files=normal"]);
  if (status) {
    throw new Error("The source repository has uncommitted changes. Commit or stash them before starting TouchCode.");
  }
  await git(sourceRoot, ["symbolic-ref", "--quiet", "--short", "HEAD"]);

  const sourceCommandCwd = path.resolve(sourceRoot, input.projectCwd);
  if (!within(sourceRoot, sourceCommandCwd)) {
    throw new Error("--cwd must stay inside the project repository");
  }
  const canonicalCommandCwd = await realpath(sourceCommandCwd);
  if (!within(sourceRoot, canonicalCommandCwd)) {
    throw new Error("--cwd resolves outside the project repository");
  }

  const worktreesRoot = input.worktreesRoot ?? path.join(
    homedir(),
    "Library",
    "Application Support",
    "TouchCode",
    "worktrees",
  );
  await mkdir(worktreesRoot, { recursive: true });
  const repositoryKey = createHash("sha256").update(sourceRoot).digest("hex").slice(0, 12);
  const worktreePath = path.join(worktreesRoot, `${repositoryKey}-${randomUUID()}`);

  await git(sourceRoot, ["worktree", "add", "--detach", worktreePath, "HEAD"]);
  const relativeCwd = path.relative(sourceRoot, canonicalCommandCwd);
  const commandCwd = path.join(worktreePath, relativeCwd);

  try {
    await linkDependencies(path.join(sourceRoot, "node_modules"), path.join(worktreePath, "node_modules"));
    if (relativeCwd) {
      await linkDependencies(
        path.join(canonicalCommandCwd, "node_modules"),
        path.join(commandCwd, "node_modules"),
      );
    }
  } catch (error) {
    await execFileAsync("git", ["worktree", "remove", "--force", worktreePath], { cwd: sourceRoot });
    throw error;
  }

  return { sourceRoot, worktreePath, commandCwd };
}

async function isListening(port: number) {
  return await new Promise<boolean>((resolve) => {
    const socket = net.createConnection({ host: "127.0.0.1", port });
    socket.setTimeout(500);
    socket.once("connect", () => {
      socket.destroy();
      resolve(true);
    });
    socket.once("timeout", () => {
      socket.destroy();
      resolve(false);
    });
    socket.once("error", () => resolve(false));
  });
}

export async function startPreview(input: {
  workspace: PreparedWorkspace;
  command: string[];
  port: number;
  timeoutMilliseconds?: number;
}): Promise<RunningPreview> {
  const [executable, ...args] = input.command;
  if (!executable) throw new Error("Preview command is empty");
  if (await isListening(input.port)) {
    throw new Error(`Preview port ${input.port} is already in use`);
  }

  const child = spawn(executable, args, {
    cwd: input.workspace.commandCwd,
    env: {
      ...process.env,
      HOST: "0.0.0.0",
      PORT: String(input.port),
    },
    stdio: "inherit",
    shell: false,
  });
  let spawnError: Error | undefined;
  child.once("error", (error) => {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") {
      spawnError = new Error(`Preview command not found: ${executable} (is it installed and in PATH?)`);
    } else {
      spawnError = error;
    }
  });

  const timeout = input.timeoutMilliseconds ?? 30_000;
  const startedAt = Date.now();
  while (Date.now() - startedAt < timeout) {
    if (spawnError) throw spawnError;
    if (child.exitCode !== null || child.signalCode !== null) {
      const hint = child.exitCode === 127 ? " (command not found)" : "";
      throw new Error(
        `Preview command exited (${child.signalCode ?? `status ${child.exitCode ?? "unknown"}`})${hint} — check that "${executable}" is installed and that "${input.workspace.commandCwd}" contains your project`,
      );
    }
    if (await isListening(input.port)) {
      return { ...input.workspace, process: child, port: input.port };
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }

  child.kill("SIGTERM");
  throw new Error(`Preview did not listen on port ${input.port} within ${timeout}ms — is the command correct? Try running it manually in ${input.workspace.commandCwd}`);
}

export async function removeFailedWorkspace(workspace: PreparedWorkspace) {
  // Remove node_modules symlink first so `git worktree remove` does not fail on untracked symlink
  const { unlink, rm } = await import("node:fs/promises");
  const candidates = [path.join(workspace.worktreePath, "node_modules"), path.join(workspace.commandCwd, "node_modules")];
  for (const p of candidates) {
    try { await unlink(p); } catch {}
    // Also handle pnpm's .pnpm virtual store if it was copied
    try { await rm(path.join(p, ".pnpm"), { recursive: true, force: true }); } catch {}
  }
  try {
    await execFileAsync("git", ["worktree", "remove", "--force", workspace.worktreePath], {
      cwd: workspace.sourceRoot,
    });
  } catch {
    // Fallback: remove directory directly if git worktree remove fails (e.g. git not found)
    const { rm: rm2 } = await import("node:fs/promises");
    await rm2(workspace.worktreePath, { recursive: true, force: true }).catch(() => undefined);
    // Prune stale worktree entry
    await execFileAsync("git", ["worktree", "prune"], { cwd: workspace.sourceRoot }).catch(() => undefined);
  }
}
