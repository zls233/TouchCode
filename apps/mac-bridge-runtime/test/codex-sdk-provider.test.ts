import assert from "node:assert/strict";
import test from "node:test";
import type { CodingRunRequest } from "@touchcode/protocol";
import { CodexSdkProvider } from "../src/coding-agents/codex-sdk-provider.js";

const request = (overrides: Partial<CodingRunRequest> = {}): CodingRunRequest => ({
  projectId: "project-1",
  worktreePath: "/tmp/worktree",
  provider: "codex",
  intent: {
    type: "edit.intent.v1",
    intentId: "intent-1",
    sessionId: "session-1",
    instruction: "Make the marked button black",
    inputMode: "text",
  },
  ...overrides,
});

test("fails clearly and does not start Codex when visual context is absent", async () => {
  let started = false;
  const events: string[] = [];
  const fakeCodex = {
    startThread() {
      started = true;
      throw new Error("must not start");
    },
  };
  const result = await new CodexSdkProvider(fakeCodex as never).run(request(), (event) => {
    events.push(event.stage);
  });

  assert.equal(result.status, "failed");
  assert.equal(result.summary, "Visual context is required for a coding run");
  assert.equal(started, false);
  assert.deepEqual(events, ["queued", "failed"]);
});

test("passes the prompt and exactly one local image to Codex", async () => {
  let input: unknown;
  let options: unknown;
  let turnOptions: unknown;
  const fakeCodex = {
    startThread(startOptions: unknown) {
      options = startOptions;
      return {
        async runStreamed(runInput: unknown, runOptions: unknown) {
          input = runInput;
          turnOptions = runOptions;
          return {
            events: (async function* () {
              yield { type: "thread.started", thread_id: "thread-1" };
              yield {
                type: "item.completed",
                item: { type: "agent_message", text: JSON.stringify({ outcome: "applied", summary: "Updated button", clarificationQuestion: null }) },
              };
            })(),
          };
        },
      };
    },
  };
  const result = await new CodexSdkProvider(fakeCodex as never).run(request({
    visualContext: {
      screenshotPath: "/tmp/capture.jpg",
      viewportWidth: 1024,
      viewportHeight: 768,
    },
  }));

  assert.equal(result.status, "succeeded");
  assert.equal(result.providerThreadId, "thread-1");
  assert.equal(result.summary, "Updated button");
  assert.deepEqual((turnOptions as { outputSchema: { required: string[] } }).outputSchema.required,
    ["outcome", "summary", "clarificationQuestion"]);
  assert.deepEqual(options, {
    workingDirectory: "/tmp/worktree",
    sandboxMode: "workspace-write",
    approvalPolicy: "never",
    networkAccessEnabled: false,
    webSearchMode: "disabled",
    threadSource: "touchcode-mac-bridge",
  });
  assert.ok(Array.isArray(input));
  assert.equal(input.length, 2);
  assert.equal(input[0].type, "text");
  assert.match(input[0].text, /User request: Make the marked button black/);
  assert.deepEqual(input[1], { type: "local_image", path: "/tmp/capture.jpg" });
});
