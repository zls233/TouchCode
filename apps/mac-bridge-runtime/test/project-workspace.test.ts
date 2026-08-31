import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdir, mkdtemp, readFile, realpath, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import net from "node:net";
import path from "node:path";
import { promisify } from "node:util";
import test from "node:test";
import {
  prepareWorkspace,
  removeFailedWorkspace,
  startPreview,
} from "../src/project-workspace.js";

const execFileAsync = promisify(execFile);

async function git(cwd: string, ...args: string[]) {
  return execFileAsync("git", args, { cwd, encoding: "utf8" });
}

async function temporaryRepository() {
  const root = await mkdtemp(path.join(tmpdir(), "touchcode-workspace-"));
  await git(root, "init", "-b", "main");
  await git(root, "config", "user.email", "touchcode-tests@example.invalid");
  await git(root, "config", "user.name", "TouchCode tests");
  await writeFile(path.join(root, "README.md"), "clean\n");
  await git(root, "add", "README.md");
  await git(root, "commit", "-m", "initial");
  return root;
}

async function withRepository(run: (root: string) => Promise<void>) {
  const root = await temporaryRepository();
  try {
    await run(root);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

test("prepares a detached worktree and keeps --cwd inside it", async () => {
  await withRepository(async (root) => {
    const appPath = path.join(root, "apps", "web");
    await writeFile(path.join(root, "README.md"), "clean\n");
    await mkdir(appPath, { recursive: true });
    await writeFile(path.join(appPath, "package.json"), "{}\n");
    await git(root, "add", ".");
    await git(root, "commit", "-m", "add app");

    const workspace = await prepareWorkspace({
      projectPath: root,
      projectCwd: "apps/web",
      worktreesRoot: path.join(root, ".touchcode-worktrees"),
    });
    assert.equal(workspace.sourceRoot, await realpath(root));
    assert.equal(workspace.commandCwd, path.join(workspace.worktreePath, "apps/web"));
    const topLevel = (await git(workspace.worktreePath, "rev-parse", "--show-toplevel")).stdout.trim();
    assert.equal(await realpath(topLevel), await realpath(workspace.worktreePath));
    assert.equal((await readFile(path.join(workspace.commandCwd, "package.json"), "utf8")), "{}\n");

    await removeFailedWorkspace(workspace);
    await assert.rejects(() => readFile(workspace.worktreePath), { code: "ENOENT" });
  });
});

test("requires an HTTP preview response before reporting readiness", async () => {
  const server = await new Promise<net.Server>((resolve, reject) => {
    const candidate = net.createServer();
    candidate.once("error", reject);
    candidate.listen(0, "127.0.0.1", () => resolve(candidate));
  });
  const address = server.address();
  assert.ok(address && typeof address !== "string");
  const port = address.port;
  server.close();

  const workspace = { sourceRoot: ".", worktreePath: ".", commandCwd: "." };
  await assert.rejects(
    () => startPreview({
      workspace,
      command: [process.execPath, "-e", `require('node:net').createServer(() => {}).listen(${port}, '127.0.0.1')`],
      port,
      timeoutMilliseconds: 700,
    }),
    /Preview did not listen on port/,
  );
});

test("requires the project path to be the Git repository root", async () => {
  await withRepository(async (root) => {
    const nested = path.join(root, "nested");
    await mkdir(nested);
    await assert.rejects(
      () => prepareWorkspace({ projectPath: nested, projectCwd: ".", worktreesRoot: path.join(root, "worktrees") }),
      /--project must point to the Git repository root/,
    );
  });
});

test("requires a clean, attached source checkout", async () => {
  await withRepository(async (root) => {
    await writeFile(path.join(root, "dirty.txt"), "uncommitted\n");
    await assert.rejects(
      () => prepareWorkspace({ projectPath: root, projectCwd: ".", worktreesRoot: path.join(root, "worktrees") }),
      /uncommitted changes/,
    );
  });

  await withRepository(async (root) => {
    await assert.rejects(
      () => git(root, "checkout", "--detach", "HEAD").then(() => prepareWorkspace({
        projectPath: root,
        projectCwd: ".",
        worktreesRoot: path.join(root, "worktrees"),
      })),
      /Command failed|symbolic-ref/,
    );
  });
});

test("rejects --cwd paths outside the repository, including symlink escapes", async () => {
  await withRepository(async (root) => {
    const outside = await mkdtemp(path.join(tmpdir(), "touchcode-outside-"));
    try {
      await assert.rejects(
        () => prepareWorkspace({ projectPath: root, projectCwd: "../outside", worktreesRoot: path.join(root, "worktrees") }),
        /--cwd must stay inside the project repository/,
      );
      await symlink(outside, path.join(root, "escape"), "dir");
      await git(root, "add", "escape");
      await git(root, "commit", "-m", "add escape symlink");
      await assert.rejects(
        () => prepareWorkspace({ projectPath: root, projectCwd: "escape", worktreesRoot: path.join(root, "worktrees") }),
        /--cwd resolves outside the project repository/,
      );
    } finally {
      await rm(outside, { recursive: true, force: true });
    }
  });
});
