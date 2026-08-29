import { realpath, stat } from "node:fs/promises";
import path from "node:path";

export class ProjectGrantStore {
  readonly #roots = new Map<string, string>();

  async grant(inputPath: string) {
    const canonicalRoot = await realpath(inputPath);
    const info = await stat(canonicalRoot);
    if (!info.isDirectory()) throw new Error("Project grant must target a directory");
    const id = crypto.randomUUID();
    this.#roots.set(id, canonicalRoot);
    return { id, canonicalRoot };
  }

  getRoot(projectId: string) {
    const root = this.#roots.get(projectId);
    if (!root) throw new Error("Unknown project grant");
    return root;
  }

  async resolve(projectId: string, relativePath: string) {
    const root = this.getRoot(projectId);
    if (path.isAbsolute(relativePath)) throw new Error("Absolute source paths are not allowed");

    const candidate = path.resolve(root, relativePath);
    const relative = path.relative(root, candidate);
    if (relative.startsWith("..") || path.isAbsolute(relative)) {
      throw new Error("Source path escapes project root");
    }
    return candidate;
  }
}

