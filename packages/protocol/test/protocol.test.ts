import assert from "node:assert/strict";
import test from "node:test";
import {
  codingRunRequestSchema,
  pairSessionRequestSchema,
  pairedWorkspaceSessionSchema,
  visualEditRequestSchema,
  visualRunRequestV2Schema,
} from "../src/index.js";

const image = Buffer.from("a".repeat(100)).toString("base64");

test("accepts a typed Pencil screenshot without DOM metadata", () => {
  const parsed = visualEditRequestSchema.parse({
    instruction: "Make the marked heading blue",
    inputMode: "text",
    annotatedImageBase64: image,
    viewportWidth: 1024,
    viewportHeight: 768,
  });
  assert.equal(parsed.provider, "codex");
  assert.equal("elements" in parsed, false);
});

test("accepts speech after it has been transcribed on iPad", () => {
  assert.equal(visualEditRequestSchema.safeParse({
    instruction: "把圈出来的按钮放大",
    inputMode: "voice",
    annotatedImageBase64: image,
    viewportWidth: 1024,
    viewportHeight: 768,
  }).success, true);
});

test("accepts an atomic multi-viewport annotation-only draft", () => {
  const parsed = visualRunRequestV2Schema.parse({
    type: "visual.run.v2",
    draftId: "draft-1",
    inputMode: "annotation",
    captures: [
      {
        annotatedImageBase64: image,
        viewport: { url: "http://127.0.0.1:5173", width: 1024, height: 768, scrollX: 0, scrollY: 400, zoomScale: 1, devicePixelRatio: 2 },
        annotationBounds: { x: 20, y: 420, width: 100, height: 60 },
        elements: [],
      },
    ],
  });
  assert.equal(parsed.provider, "codex");
  assert.equal(parsed.instruction, undefined);
});

test("rejects a text draft without text", () => {
  assert.equal(visualRunRequestV2Schema.safeParse({
    type: "visual.run.v2", draftId: "draft-1", inputMode: "text", captures: [{
      annotatedImageBase64: image,
      viewport: { url: "http://127.0.0.1:5173", width: 1, height: 1, scrollX: 0, scrollY: 0, zoomScale: 1, devicePixelRatio: 1 },
      annotationBounds: { x: 0, y: 0, width: 1, height: 1 }, elements: [],
    }],
  }).success, false);
});

test("requires a six digit pairing code", () => {
  assert.equal(pairSessionRequestSchema.safeParse({ pairingCode: "123456" }).success, true);
  assert.equal(pairSessionRequestSchema.safeParse({ pairingCode: "12345" }).success, false);
});

test("paired sessions do not expose local project paths", () => {
  const session = pairedWorkspaceSessionSchema.parse({
    sessionId: "session-1",
    previewURL: "http://192.168.1.2:5173",
    bridgeURL: "http://192.168.1.2:4317",
    pairingCode: "123456",
    ipadConnected: true,
    latestRunId: null,
    errorMessage: null,
    clientToken: "a".repeat(64),
  });
  assert.equal("worktreePath" in session, false);
});

test("requires image context for every coding run", () => {
  assert.equal(codingRunRequestSchema.safeParse({
    projectId: "project-1",
    worktreePath: "/tmp/worktree",
    provider: "codex",
    intent: {
      type: "edit.intent.v1",
      intentId: "intent-1",
      sessionId: "session-1",
      instruction: "Change it",
      inputMode: "text",
    },
    visualContext: {
      screenshotPath: "/tmp/capture.jpg",
      viewportWidth: 1024,
      viewportHeight: 768,
    },
  }).success, true);
});
