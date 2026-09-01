import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { promisify } from "node:util";
import { WorkspaceCheckpoint } from "../src/run-checkpoint.js";

const execFileAsync = promisify(execFile);

test("restores the exact pre-run worktree and removes only files created by the run", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "touchcode-checkpoint-test-"));
  await execFileAsync("git", ["init", "--quiet"], { cwd: root });
  await writeFile(path.join(root, "tracked.txt"), "baseline\n");
  await execFileAsync("git", ["add", "tracked.txt"], { cwd: root });
  await execFileAsync("git", ["-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "--quiet", "-m", "baseline"], { cwd: root });
  await writeFile(path.join(root, "tracked.txt"), "pre-run edit\n");
  await writeFile(path.join(root, "existing-untracked.txt"), "keep me\n");

  const checkpoint = await WorkspaceCheckpoint.create(root);
  assert.ok(checkpoint);
  await writeFile(path.join(root, "tracked.txt"), "agent edit\n");
  await writeFile(path.join(root, "existing-untracked.txt"), "agent changed untracked\n");
  await writeFile(path.join(root, "agent-created.txt"), "remove me\n");

  await checkpoint.rollback();
  assert.equal(await readFile(path.join(root, "tracked.txt"), "utf8"), "pre-run edit\n");
  assert.equal(await readFile(path.join(root, "existing-untracked.txt"), "utf8"), "keep me\n");
  await assert.rejects(readFile(path.join(root, "agent-created.txt")));
  await checkpoint.dispose();
});

test("includes staged edits in the review diff", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "touchcode-checkpoint-staged-"));
  await execFileAsync("git", ["init", "--quiet"], { cwd: root });
  await writeFile(path.join(root, "tracked.txt"), "baseline\n");
  await execFileAsync("git", ["add", "tracked.txt"], { cwd: root });
  await execFileAsync("git", ["-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "--quiet", "-m", "baseline"], { cwd: root });

  const checkpoint = await WorkspaceCheckpoint.create(root);
  assert.ok(checkpoint);
  await writeFile(path.join(root, "tracked.txt"), "agent edit\n");
  await execFileAsync("git", ["add", "tracked.txt"], { cwd: root });

  const changes = await checkpoint.collectChanges();
  assert.deepEqual(changes.changedFiles, ["tracked.txt"]);
  assert.match(changes.diff, /agent edit/);
  await checkpoint.dispose();
});
