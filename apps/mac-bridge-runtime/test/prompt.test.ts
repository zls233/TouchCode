import assert from "node:assert/strict";
import test from "node:test";
import { buildCodingPrompt } from "../src/coding-agents/prompt.js";

test("builds image-only coding context without DOM metadata", () => {
  const prompt = buildCodingPrompt({
    projectId: "project-1",
    worktreePath: "/tmp/worktree",
    provider: "codex",
    intent: {
      type: "edit.intent.v1",
      intentId: "intent-1",
      sessionId: "session-1",
      instruction: "Make the marked button black",
      inputMode: "voice",
    },
    visualContext: {
      screenshotPath: "/tmp/capture.jpg",
      viewportWidth: 1024,
      viewportHeight: 768,
    },
  });

  assert.match(prompt, /User request: Make the marked button black/);
  assert.match(prompt, /Input mode: voice/);
  assert.match(prompt, /no DOM, component, selector/);
  assert.doesNotMatch(prompt, /Visible element candidates/);
});
