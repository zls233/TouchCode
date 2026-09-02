import assert from "node:assert/strict";
import test from "node:test";
import { isAllowedTunnelTarget } from "../src/tunnel-gateway.js";

test("tunnel gateway only allows localhost vite port", () => {
  assert.equal(isAllowedTunnelTarget("http://127.0.0.1:5173/", 5173), true);
  assert.equal(isAllowedTunnelTarget("http://localhost:5173/src/main.tsx", 5173), true);
  assert.equal(isAllowedTunnelTarget("http://127.0.0.1:5173/__vite_hmr", 5173), true);
  // Wrong port
  assert.equal(isAllowedTunnelTarget("http://127.0.0.1:3000/", 5173), false);
  // Non-loopback hosts
  assert.equal(isAllowedTunnelTarget("http://192.168.1.10:5173/", 5173), false);
  assert.equal(isAllowedTunnelTarget("http://example.com:5173/", 5173), false);
  assert.equal(isAllowedTunnelTarget("http://127.0.0.1:5173/../etc/passwd", 5173), true); // path traversal handled elsewhere, host still loopback
  // Invalid URL
  assert.equal(isAllowedTunnelTarget("not-a-url", 5173), false);
  assert.equal(isAllowedTunnelTarget("http://[::1]:5173/", 5173), true);
});

test("tunnel gateway rejects arbitrary destinations", () => {
  // Ensure that even with correct port, non-loopback is rejected
  assert.equal(isAllowedTunnelTarget("http://10.0.0.5:5173/", 5173), false);
  assert.equal(isAllowedTunnelTarget("https://127.0.0.1:5173/", 5173), true); // https also allowed if same port
  // Different scheme but same host/port still loopback check passes
  assert.equal(isAllowedTunnelTarget("http://127.0.0.1:5173", 5173), true);
});
