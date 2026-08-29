import { Codex, type ThreadEvent } from "@openai/codex-sdk";
import type { CodingRunRequest, CodingRunResult } from "@touchcode/protocol";
import { buildCodingPrompt } from "./prompt.js";
import type { CodingAgentProvider, CodingRunObserver, CodingRunStage } from "./provider.js";

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

    try {
      const thread = this.codex.startThread({
        workingDirectory: request.worktreePath,
        sandboxMode: "workspace-write",
        approvalPolicy: "never",
        networkAccessEnabled: false,
        webSearchMode: "disabled",
        threadSource: "touchcode-mac-bridge",
      });
      const prompt = buildCodingPrompt(request);
      const input = request.visualContext
        ? [
            { type: "text" as const, text: prompt },
            { type: "local_image" as const, path: request.visualContext.screenshotPath },
          ]
        : prompt;
      const streamed = await thread.runStreamed(input);

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
            message: stage === "editing" ? "Coding agent is updating the worktree" : `Codex ${stage}`,
          });
        }
        if (event.type === "turn.failed") throw new Error(event.error.message);
        if (event.type === "error") throw new Error(event.message);
      }

      return {
        runId,
        provider: this.kind,
        ...(providerThreadId ? { providerThreadId } : {}),
        status: "succeeded",
        summary,
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
      };
    }
  }
}
