import type { CodingRunRequest, CodingRunSnapshot } from "@touchcode/protocol";
import type { CodingAgentProvider } from "./coding-agents/provider.js";
import { WorkspaceCheckpoint } from "./run-checkpoint.js";
import { mkdir, readdir, stat, writeFile } from "node:fs/promises";
import path from "node:path";

type ManagedRun = CodingRunSnapshot;

export class DemoRunManager {
  readonly #runs = new Map<string, ManagedRun>();
  readonly #subscribers = new Map<string, Set<(run: ManagedRun) => void>>();
  readonly #previewCounters = new Map<string, number>();
  // Retain checkpoint for reviewable runs until Keep/Undo decides. Kept runs stay disposed.
  readonly #pendingCheckpoints = new Map<string, WorkspaceCheckpoint>();

  create(sessionId: string, request: CodingRunRequest, provider: CodingAgentProvider) {
    const active = Array.from(this.#runs.values()).find(
      (run) => run.sessionId === sessionId && (run.status === "queued" || run.status === "running"),
    );
    if (active) throw new Error("A coding run is already active for this session");

    const now = new Date().toISOString();
    const run: ManagedRun = {
      runId: crypto.randomUUID(),
      sessionId,
      provider: request.provider,
      stage: "queued",
      status: "queued",
      message: "Queued for Codex",
      summary: "",
      decision: "pending",
      diff: "",
      changedFiles: [],
      previewRevision: null,
      outcome: "applied",
      clarificationQuestion: null,
      startedAt: now,
      updatedAt: now,
    };
    this.#runs.set(run.runId, run);
    void this.execute(run, request, provider);
    return { ...run };
  }

  get(runId: string) {
    const run = this.#runs.get(runId);
    if (!run) throw new Error("Unknown coding run");
    return run;
  }

  forSession(sessionId: string, runId: string) {
    const run = this.get(runId);
    if (run.sessionId !== sessionId) throw new Error("Coding run does not belong to this session");
    return { ...run };
  }

  subscribe(sessionId: string, runId: string, listener: (run: CodingRunSnapshot) => void) {
    const run = this.forSession(sessionId, runId);
    const listeners = this.#subscribers.get(runId) ?? new Set();
    listeners.add(listener);
    this.#subscribers.set(runId, listeners);
    listener(run);
    return () => {
      listeners.delete(listener);
      if (listeners.size === 0) this.#subscribers.delete(runId);
    };
  }

  private publish(run: ManagedRun) {
    for (const listener of this.#subscribers.get(run.runId) ?? []) listener({ ...run });
  }

  private nextPreviewRevision(sessionId: string): string {
    const next = (this.#previewCounters.get(sessionId) ?? 0) + 1;
    this.#previewCounters.set(sessionId, next);
    return String(next);
  }

  async decide(sessionId: string, runId: string, action: "keep" | "undo"): Promise<ManagedRun> {
    const run = this.forSession(sessionId, runId);
    const stored = this.#runs.get(runId)!;
    if (stored.status !== "succeeded") throw new Error("Only succeeded runs can be decided");
    if (stored.decision !== "pending") throw new Error("Run already decided");
    stored.decision = action === "keep" ? "approved" : "rejected";
    stored.updatedAt = new Date().toISOString();
    if (action === "undo") {
      const checkpoint = this.#pendingCheckpoints.get(runId);
      if (checkpoint) {
        try {
          await checkpoint.rollback();
          stored.changedFiles = [];
          stored.diff = "";
        } catch {}
        await checkpoint.dispose().catch(() => undefined);
        this.#pendingCheckpoints.delete(runId);
      } else {
        stored.changedFiles = [];
        stored.diff = "";
      }
    } else {
      // Keep: retain changes and dispose checkpoint.
      const checkpoint = this.#pendingCheckpoints.get(runId);
      if (checkpoint) {
        await checkpoint.dispose().catch(() => undefined);
        this.#pendingCheckpoints.delete(runId);
      }
    }
    this.publish(stored);
    return { ...stored };
  }

  private async execute(run: ManagedRun, request: CodingRunRequest, provider: CodingAgentProvider) {
    const checkpoint = await WorkspaceCheckpoint.create(request.worktreePath);
    if (checkpoint) this.#pendingCheckpoints.set(run.runId, checkpoint);
    run.status = "running";
    run.updatedAt = new Date().toISOString();
    this.publish(run);
    try {
      const result = await provider.run(request, (event) => {
        run.stage = event.stage;
        run.message = event.message;
        run.updatedAt = new Date().toISOString();
        this.publish(run);
      });
      if (result.outcome !== "applied") {
        await checkpoint?.rollback().catch(() => undefined);
        if (checkpoint) {
          await checkpoint.dispose().catch(() => undefined);
          this.#pendingCheckpoints.delete(run.runId);
        }
      } else if (checkpoint) {
        const changes = await checkpoint.collectChanges().catch(() => null);
        if (changes) {
          run.changedFiles = changes.changedFiles;
          run.diff = changes.diff;
        }
        // Keep checkpoint for Keep/Undo review; do not dispose yet.
      }
      run.summary = result.summary;
      run.status = result.status;
      run.stage = result.status === "succeeded" ? "completed" : "failed";
      run.outcome = result.status === "succeeded" ? result.outcome : "failed";
      run.clarificationQuestion = result.clarificationQuestion;
      if (result.status === "succeeded" && result.outcome === "applied") {
        run.previewRevision = this.nextPreviewRevision(run.sessionId);
        // Write precise revision file for Demo Web to sync HMR without drift.
        // Vite serves `public/` at `/` relative to its root (which may be worktreePath or worktreePath/<relativeCwd>).
        // Write to every plausible public dir under worktreePath to ensure fetch("/__touchcode_preview_revision.json") succeeds.
        void (async () => {
          try {
            const payload = JSON.stringify({ revision: run.previewRevision, runId: run.runId });
            const candidates = new Set<string>([path.join(request.worktreePath, "public")]);
            // Heuristically find Vite roots (index.html or vite.config.*) within 2 levels
            const searchRoots = [request.worktreePath];
            try {
              const entries = await readdir(request.worktreePath, { withFileTypes: true });
              for (const e of entries) {
                if (e.isDirectory() && !e.name.startsWith(".") && !e.name.startsWith("node_modules")) {
                  const sub = path.join(request.worktreePath, e.name);
                  searchRoots.push(sub);
                  try {
                    const subEntries = await readdir(sub, { withFileTypes: true });
                    for (const se of subEntries) {
                      if (se.isDirectory() && !se.name.startsWith(".") && !se.name.startsWith("node_modules")) {
                        searchRoots.push(path.join(sub, se.name));
                      }
                    }
                  } catch {}
                }
              }
            } catch {}
            for (const root of searchRoots) {
              try {
                const hasIndex = await stat(path.join(root, "index.html")).then(() => true).catch(() => false);
                const hasViteConfig = await Promise.any([
                  stat(path.join(root, "vite.config.ts")).then(() => true).catch(() => false),
                  stat(path.join(root, "vite.config.js")).then(() => true).catch(() => false),
                  stat(path.join(root, "vite.config.mjs")).then(() => true).catch(() => false),
                ]).catch(() => false);
                if (hasIndex || hasViteConfig) candidates.add(path.join(root, "public"));
              } catch {}
            }
            for (const dir of candidates) {
              try {
                await mkdir(dir, { recursive: true });
                await writeFile(path.join(dir, "__touchcode_preview_revision.json"), payload, "utf8");
                // Also write at Vite root for fallback fetch("/public/__touchcode_preview_revision.json")
                await writeFile(path.join(path.dirname(dir), "__touchcode_preview_revision.json"), payload, "utf8").catch(() => {});
              } catch {}
            }
          } catch {}
        })();
        // Decision stays pending for review; Mac app will call keep/undo.
        run.decision = "pending";
      } else {
        run.previewRevision = null;
        run.changedFiles = [];
        run.diff = "";
        run.decision = "pending";
        if (checkpoint) {
          await checkpoint.dispose().catch(() => undefined);
          this.#pendingCheckpoints.delete(run.runId);
        }
      }
      run.message = result.outcome === "needs_clarification"
        ? result.clarificationQuestion ?? "Codex needs clarification"
        : result.status === "succeeded" ? "Preview ready" : result.summary;
      this.publish(run);
    } catch (error) {
      await checkpoint?.rollback().catch(() => undefined);
      if (checkpoint) {
        await checkpoint.dispose().catch(() => undefined);
        this.#pendingCheckpoints.delete(run.runId);
      }
      run.status = "failed";
      run.stage = "failed";
      run.summary = error instanceof Error ? error.message : "Coding run failed";
      run.message = run.summary;
      run.outcome = "failed";
      run.previewRevision = null;
      run.changedFiles = [];
      run.diff = "";
      run.decision = "pending";
      this.publish(run);
    } finally {
      run.updatedAt = new Date().toISOString();
      this.publish(run);
      // For applied+pending review, checkpoint is retained; otherwise disposed above.
      // Fallback dispose if still pending and not applied (safety).
      if (run.outcome !== "applied" || run.status !== "succeeded") {
        const cp = this.#pendingCheckpoints.get(run.runId);
        if (cp) {
          await cp.dispose().catch(() => undefined);
          this.#pendingCheckpoints.delete(run.runId);
        }
      }
    }
  }
}
