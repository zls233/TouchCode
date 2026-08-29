import assert from "node:assert/strict";
import test from "node:test";
import { createBridgeApp } from "../src/app.js";

test("identifies itself as a bridge rather than a coding agent", async () => {
  const app = await createBridgeApp();
  const response = await app.inject({ method: "GET", url: "/health" });
  assert.equal(response.statusCode, 200);
  assert.deepEqual(response.json(), {
    status: "ok",
    service: "touchcode-mac-bridge",
    role: "bridge",
    version: "0.1.0",
  });
  await app.close();
});
