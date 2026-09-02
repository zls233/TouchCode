import assert from "node:assert/strict";
import test from "node:test";
import { ChannelMultiplexer } from "../src/session-channels.js";

test("control messages are not blocked by large file", async () => {
  const mux = new ChannelMultiplexer();
  const filePayload = new Uint8Array(200 * 1024).fill(0x41);
  const fileMsg = { id: "file-1", channel: "file" as const, payload: filePayload, sentAt: Date.now() };
  const controlMsg = { id: "ctrl-1", channel: "control" as const, payload: new Uint8Array(Buffer.from("ping")), sentAt: Date.now() };

  const fileTask = mux.send(fileMsg);
  // Give file a moment to start chunking
  await new Promise((r) => setTimeout(r, 2));
  const start = Date.now();
  await mux.send(controlMsg);
  const elapsed = Date.now() - start;
  assert.ok(elapsed < 50, `control blocked for ${elapsed}ms`);
  await fileTask;
  const received = mux.tryReceive("control");
  assert.ok(received);
  assert.equal(received?.id, "ctrl-1");
  // File should have been chunked into 4 messages in its queue (if not yet consumed)
  // We sent file first, so its chunks are in file queue; control is separate
  const fileFirst = mux.tryReceive("file");
  assert.ok(fileFirst);
});

test("oversize payload is rejected", async () => {
  const mux = new ChannelMultiplexer();
  const large = new Uint8Array(1 * 1024 * 1024 + 1);
  const msg = { id: "big", channel: "file" as const, payload: large, sentAt: Date.now() };
  await assert.rejects(() => mux.send(msg), /payloadTooLarge/);
});

test("channel receive waits for message", async () => {
  const mux = new ChannelMultiplexer();
  const msg = { id: "a", channel: "codex" as const, payload: new Uint8Array([1, 2, 3]), sentAt: Date.now() };
  const recv = mux.receive("codex");
  await new Promise((r) => setTimeout(r, 5));
  await mux.send(msg);
  const got = await recv;
  assert.equal(got.id, "a");
});
