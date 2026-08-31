import { Codex, type ThreadEvent } from "@openai/codex-sdk";
import type { CodingRunRequest, CodingRunResult } from "@touchcode/protocol";
import { buildCodingPrompt } from "./prompt.js";
import type { CodingAgentProvider, CodingRunObserver, CodingRunStage } from "./provider.js";

type ProviderOutcome = "applied" | "needs_clarification" | "no_change";

const outcomeSchema = {
  type: "object",
  additionalProperties: false,
  required: ["outcome", "summary", "clarificationQuestion"],
  properties: {
    outcome: { type: "string", enum: ["applied", "needs_clarification", "no_change"] },
    summary: { type: "string" },
    clarificationQuestion: { type: ["string", "null"] },
  },
} as const;

function parseStructuredOutcome(message: string): {
  outcome: ProviderOutcome;
  summary: string;
  clarificationQuestion: string | null;
} {
  try {
    const parsed = JSON.parse(message) as { outcome?: ProviderOutcome; summary?: string; clarificationQuestion?: string | null };
    if (!parsed.outcome || !["applied", "needs_clarification", "no_change"].includes(parsed.outcome)) {
      throw new Error("Codex returned an invalid visual-edit outcome");
    }
    return {
      outcome: parsed.outcome,
      summary: parsed.summary?.trim() || "Codex completed.",
      clarificationQuestion: parsed.clarificationQuestion?.trim() || null,
    };
  } catch (error) {
    throw new Error("Codex did not return the required structured visual-edit outcome", { cause: error });
  }
}

function stageForEvent(event: ThreadEvent): CodingRunStage | undefined {
  if (event.type === "thread.started") return "connecting";
  if (event.type === "turn.started") return "reasoning";
  if (event.type === "turn.failed" || event.type === "error") return "failed";
  if (event.type !== "item.started" && event.type !== "item.updated" && event.type !== "item.completed") {
    return event.type === "turn.completed" ? "completed" : undefined;
  }
  if (event.item.type === "file_change" || event.item.type === "command_execution") return "editing";
  if (event.item.type === "reasoning" || event.item.type === "todo_list") return "reasoning";
  return undefined;
}

export class CodexSdkProvider implements CodingAgentProvider {
  readonly kind = "codex" as const;

  constructor(private readonly codex = new Codex()) {}

  async isAvailable() {
    return true;
  }

  async run(request: CodingRunRequest, observe?: CodingRunObserver): Promise<CodingRunResult> {
    const runId = crypto.randomUUID();
    let providerThreadId: string | undefined;
    let summary = "Codex completed without a final message.";
    observe?.({ runId, provider: this.kind, stage: "queued", message: "Queued for Codex" });
    const visualContext = request.visualContext;
    if (!visualContext) {
      const message = "Visual context is required for a coding run";
      observe?.({ runId, provider: this.kind, stage: "failed", message });
      return {
        runId,
        provider: this.kind,
        status: "failed",
        summary: message,
        outcome: "failed",
        clarificationQuestion: null,
      };
    }

    try {
      const thread = this.codex.startThread({
        workingDirectory: request.worktreePath,
        sandboxMode: "workspace-write",
        approvalPolicy: "never",
        networkAccessEnabled: false,
        webSearchMode: "disabled",
        threadSource: "touchcode-mac-bridge",
      });
      const streamed = await thread.runStreamed([
        { type: "text", text: buildCodingPrompt(request) },
        ...(visualContext.screenshotPaths ?? [visualContext.screenshotPath]).map((imagePath) => ({
          type: "local_image" as const,
          path: imagePath,
        })),
      ], { outputSchema: outcomeSchema });

      for await (const event of streamed.events) {
        if (event.type === "thread.started") providerThreadId = event.thread_id;
        if (event.type === "item.completed" && event.item.type === "agent_message") {
          summary = event.item.text;
        }
        const stage = stageForEvent(event);
        if (stage) {
          observe?.({
            runId,
            provider: this.kind,
            stage,
            message: stage === "editing" ? "Codex is updating the webpage" : `Codex ${stage}`,
          });
        }
        if (event.type === "turn.failed") throw new Error(event.error.message);
        if (event.type === "error") throw new Error(event.message);
      }

      const outcome = parseStructuredOutcome(summary);
      return {
        runId,
        provider: this.kind,
        ...(providerThreadId ? { providerThreadId } : {}),
        status: "succeeded",
        ...outcome,
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : "Codex run failed";
      observe?.({ runId, provider: this.kind, stage: "failed", message });
      return {
        runId,
        provider: this.kind,
        ...(providerThreadId ? { providerThreadId } : {}),
        status: "failed",
        summary: message,
        outcome: "failed",
        clarificationQuestion: null,
      };
    }
  }
}
