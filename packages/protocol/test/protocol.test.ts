import assert from "node:assert/strict";
import test from "node:test";
import { codingRunRequestSchema, elementSelectionSchema } from "../src/index.js";

const selection = {
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
    elementId: "button.cta",
    tag: "button",
    role: "button",
    text: "Start",
    domPath: "main>button",
    rect: { x: 400, y: 300, width: 120, height: 44 },
    framework: "react",
    componentName: "CTA",
    source: { file: "src/CTA.tsx", line: 10, column: 4 },
    sourceStack: [],
  },
} as const;

test("accepts a React element selection", () => {
  assert.equal(elementSelectionSchema.parse(selection).target.source?.file, "src/CTA.tsx");
});

test("rejects normalized points outside the viewport", () => {
  const invalid = structuredClone(selection) as any;
  invalid.gesture.normalizedPoints[0].x = 2;
  assert.equal(elementSelectionSchema.safeParse(invalid).success, false);
});

test("keeps the bridge separate from the selected coding agent", () => {
  const request = codingRunRequestSchema.parse({
    projectId: "project-1",
    worktreePath: "/tmp/touchcode-worktree",
    provider: "codex",
    intent: {
      type: "edit.intent.v1",
      intentId: "intent-1",
      sessionId: "session-1",
      selectionEventId: "event-1",
      instruction: "Make the button black",
      inputMode: "text",
    },
    selection,
  });
  assert.equal(request.provider, "codex");
});
