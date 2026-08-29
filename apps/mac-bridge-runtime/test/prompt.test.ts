import assert from "node:assert/strict";
import test from "node:test";
import { buildCodingPrompt } from "../src/coding-agents/prompt.js";

test("builds coding context without assigning agent responsibility to the bridge", () => {
  const prompt = buildCodingPrompt({
    projectId: "project-1",
    worktreePath: "/tmp/worktree",
    provider: "codex",
    intent: {
      type: "edit.intent.v1",
      intentId: "intent-1",
      sessionId: "session-1",
      selectionEventId: "event-1",
      instruction: "Make this button black",
      inputMode: "text",
    },
    selection: {
      type: "element.selection.v1",
      eventId: "event-1",
      sessionId: "session-1",
      occurredAt: "2026-08-25T00:00:00.000Z",
      page: {
        url: "/",
        viewportWidth: 1024,
        viewportHeight: 768,
        scrollX: 0,
        scrollY: 0,
        zoomScale: 1,
      },
      gesture: { kind: "tap", normalizedPoints: [{ x: 0.5, y: 0.5 }] },
      target: {
        elementId: "cta",
        tag: "button",
        role: "button",
        text: "Start",
        domPath: "main>button",
        rect: { x: 1, y: 1, width: 100, height: 40 },
        framework: "react",
        componentName: "CTA",
        source: { file: "src/CTA.tsx", line: 10, column: 2 },
        sourceStack: [],
      },
    },
  });

  assert.match(prompt, /User request: Make this button black/);
  assert.match(prompt, /Source: src\/CTA\.tsx:10:2/);
  assert.match(prompt, /coding agent selected by the user through TouchCode/);
});
