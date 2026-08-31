import { execFile } from "node:child_process";
import { copyFile, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

async function git(cwd: string, args: string[], indexFile?: string) {
  const result = await execFileAsync("git", args, {
    cwd,
    encoding: "utf8",
    env: indexFile ? { ...process.env, GIT_INDEX_FILE: indexFile } : process.env,
  });
  return result.stdout;
}

function zeroSeparated(value: string) {
  return value.split("\0").filter(Boolean);
}

export class WorkspaceCheckpoint {
  private constructor(
    private readonly root: string,
    private readonly temporaryRoot: string,
    private readonly indexFile: string,
    private readonly untrackedBefore: Set<string>,
  ) {}

  static async create(worktreePath: string) {
    try {
      const root = (await git(worktreePath, ["rev-parse", "--show-toplevel"])).trim();
      const temporaryRoot = await mkdtemp(path.join(tmpdir(), "touchcode-run-checkpoint-"));
      const indexFile = path.join(temporaryRoot, "index");
      const sourceIndex = (await git(root, ["rev-parse", "--git-path", "index"])).trim();
      await copyFile(path.resolve(root, sourceIndex), indexFile);
      const untrackedBefore = new Set(zeroSeparated(await git(root, ["ls-files", "--others", "--exclude-standard", "-z"])));
      await git(root, ["add", "-A"], indexFile);
      return new WorkspaceCheckpoint(root, temporaryRoot, indexFile, untrackedBefore);
    } catch {
      return null;
    }
  }

  async collectChanges(): Promise<{ changedFiles: string[]; diff: string }> {
    // Compare current worktree against the pre-run index snapshot.
    // Use temporary index's contents as base: diff against HEAD plus untracked.
    const [nameOnly, diff, stagedDiff, untracked] = await Promise.all([
      git(this.root, ["diff", "--name-only", "-z"]).then(zeroSeparated).catch(() => [] as string[]),
      git(this.root, ["diff", "--no-color"]).catch(() => ""),
      git(this.root, ["diff", "--cached", "--no-color"]).catch(() => ""),
      git(this.root, ["ls-files", "--others", "--exclude-standard", "-z"]).then(zeroSeparated).catch(() => [] as string[]),
    ]);
    // Also include staged changes vs HEAD
    const staged = await git(this.root, ["diff", "--cached", "--name-only", "-z"]).then(zeroSeparated).catch(() => [] as string[]);
    const changedSet = new Set<string>([...nameOnly, ...staged]);
    for (const file of untracked) {
      if (!this.untrackedBefore.has(file)) changedSet.add(file);
    }
    const changedFiles = Array.from(changedSet).sort();
    // Limit diff size to avoid huge payloads (64 KiB)
    const combinedDiff = [diff, stagedDiff].filter(Boolean).join("\n");
    const trimmedDiff = combinedDiff.length > 64 * 1024 ? combinedDiff.slice(0, 64 * 1024) + "\n… diff truncated" : combinedDiff;
    return { changedFiles, diff: trimmedDiff };
  }

  async rollback() {
    const untrackedAfter = zeroSeparated(await git(this.root, ["ls-files", "--others", "--exclude-standard", "-z"]));
    await git(this.root, ["checkout-index", "--all", "--force"], this.indexFile);
    for (const relative of untrackedAfter) {
      if (this.untrackedBefore.has(relative)) continue;
      const candidate = path.resolve(this.root, relative);
      const boundary = path.relative(this.root, candidate);
      if (!boundary || boundary.startsWith("..") || path.isAbsolute(boundary)) continue;
      await rm(candidate, { force: true });
    }
  }

  async dispose() { await rm(this.temporaryRoot, { recursive: true, force: true }); }
}
