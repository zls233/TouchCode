import assert from "node:assert/strict";
import test from "node:test";
import {
  consumeHostIdentityFromEnvironment,
  hostIdentityEnvironmentKey,
  hostIdentityFromEnvironment,
  maximumHostIdentityEnvironmentBytes,
} from "../src/host-identity.js";

const identity = {
  version: 1,
  deviceId: "tcid1_-s9yHQa79RESg-U5J-5mWMBi0wuM3v-kclPZExMG2v0",
  keyAlgorithm: "p256",
  signatureAlgorithm: "ecdsa-sha256",
  signatureEncoding: "asn1-der",
  publicKeyX963: "BMFNoWM3YHGMzbG97Zqo6wWc-PE0O6k6P719hkzzq3uJwEUYgyR9miVjotMrt-mWy1Mpi2PJ5Icu4SmpFJ7hyvk",
  displayName: "TouchCode Mac",
};

test("host identity environment is optional for legacy CLI launches", () => {
  assert.equal(hostIdentityFromEnvironment({}), undefined);
});

test("host identity environment accepts a protocol-compatible public identity", () => {
  assert.deepEqual(hostIdentityFromEnvironment({
    [hostIdentityEnvironmentKey]: JSON.stringify(identity),
  }), identity);
});

test("host identity environment fails closed for malformed or mismatched values", () => {
  assert.throws(
    () => hostIdentityFromEnvironment({ [hostIdentityEnvironmentKey]: "{" }),
    /not valid JSON/,
  );
  assert.throws(
    () => hostIdentityFromEnvironment({
      [hostIdentityEnvironmentKey]: JSON.stringify({ ...identity, deviceId: "tcid1_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" }),
    }),
    /does not match device identity v1/,
  );
  assert.throws(
    () => hostIdentityFromEnvironment({
      [hostIdentityEnvironmentKey]: JSON.stringify({ ...identity, privateKey: "must-not-cross-process-boundary" }),
    }),
    /does not match device identity v1/,
  );
  assert.throws(
    () => hostIdentityFromEnvironment({
      [hostIdentityEnvironmentKey]: "x".repeat(maximumHostIdentityEnvironmentBytes + 1),
    }),
    /too large/,
  );
});

test("entrypoint handoff is removed before Bridge launches child processes", () => {
  const validEnvironment = {
    [hostIdentityEnvironmentKey]: JSON.stringify(identity),
  };
  assert.deepEqual(consumeHostIdentityFromEnvironment(validEnvironment), identity);
  assert.equal(hostIdentityEnvironmentKey in validEnvironment, false);

  const invalidEnvironment = { [hostIdentityEnvironmentKey]: "{" };
  assert.throws(() => consumeHostIdentityFromEnvironment(invalidEnvironment), /not valid JSON/);
  assert.equal(hostIdentityEnvironmentKey in invalidEnvironment, false);
});
