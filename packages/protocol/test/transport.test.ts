import assert from "node:assert/strict";
import test from "node:test";
import {
  nextReconnectDelay,
  touchCodeEnvelopeSchema,
  transportFrameLimits,
  validateEnvelopeBytes,
  validateHelloBytes,
} from "../src/transport.js";

test("hello and envelope byte limits reject oversize", () => {
  assert.throws(() => validateHelloBytes(new Uint8Array(transportFrameLimits.maxHelloBytes + 1)), /hello exceeds/);
  assert.doesNotThrow(() => validateHelloBytes(new Uint8Array(transportFrameLimits.maxHelloBytes)));
  assert.throws(() => validateEnvelopeBytes(new Uint8Array(transportFrameLimits.maxEnvelopeBytes + 1)), /envelope exceeds/);
  assert.doesNotThrow(() => validateEnvelopeBytes(new Uint8Array(transportFrameLimits.maxEnvelopeBytes)));
});

test("exponential backoff caps at 30s", () => {
  assert.equal(nextReconnectDelay(0), 500);
  assert.equal(nextReconnectDelay(1), 1000);
  assert.equal(nextReconnectDelay(2), 2000);
  assert.equal(nextReconnectDelay(6), 30000);
  assert.equal(nextReconnectDelay(10), 30000);
  assert.throws(() => nextReconnectDelay(-1), /non-negative/);
});

test("envelope schema validates version and payload size", () => {
  const base = { version: 1, id: "11111111-1111-4111-8111-111111111111", kind: "heartbeat.ping" as const, payload: { ok: true } };
  assert.equal(touchCodeEnvelopeSchema.safeParse(base).success, true);
  assert.equal(touchCodeEnvelopeSchema.safeParse({ ...base, version: 2 }).success, false);
  // Oversize payload
  const largePayload = "x".repeat(transportFrameLimits.maxPayloadBytes + 1);
  assert.equal(touchCodeEnvelopeSchema.safeParse({ ...base, payload: largePayload }).success, false);
});

test("heartbeat envelope kind is validated", () => {
  assert.equal(touchCodeEnvelopeSchema.safeParse({ version: 1, id: "22222222-2222-4222-8222-222222222222", kind: "hello", payload: null }).success, true);
  assert.equal(touchCodeEnvelopeSchema.safeParse({ version: 1, id: "33333333-3333-4333-8333-333333333333", kind: "unknown" as unknown as string, payload: null }).success, false);
});
