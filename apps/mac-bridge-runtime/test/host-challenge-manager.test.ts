import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import test from "node:test";
import {
  deriveDeviceId,
  deviceTrustChallengeResponseSchema,
  encodeBase64URL,
  verifyP256DERSignature,
  buildHostChallengeTranscript,
  type DeviceIdentity,
  type DeviceTrustChallengeRequest,
} from "@touchcode/protocol";
import {
  HostChallengeError,
  HostChallengeManager,
} from "../src/host-challenge-manager.js";

function fixture() {
  const host = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const client = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const raw = (key: typeof host.publicKey) => {
    const jwk = key.export({ format: "jwk" });
    return Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x!, "base64url"), Buffer.from(jwk.y!, "base64url")]).toString("base64url");
  };
  const hostKey = raw(host.publicKey);
  const clientKey = raw(client.publicKey);
  const identity: DeviceIdentity = {
    version: 1,
    deviceId: deriveDeviceId(hostKey),
    keyAlgorithm: "p256",
    signatureAlgorithm: "ecdsa-sha256",
    signatureEncoding: "asn1-der",
    publicKeyX963: hostKey,
    displayName: "TouchCode Mac",
  };
  const request: DeviceTrustChallengeRequest = {
    version: 1,
    purpose: "pair",
    hostDeviceId: identity.deviceId,
    clientDeviceId: deriveDeviceId(clientKey),
    clientPublicKeyX963: clientKey,
    clientDisplayName: "iPad",
    clientNonce: encodeBase64URL(Buffer.alloc(32, 0x22)),
  };
  return { host, identity, request };
}

test("issues a schema-valid signed challenge and consumes it once", async () => {
  const value = fixture();
  let now = 1_788_314_400_000;
  let randomCall = 0;
  const manager = new HostChallengeManager({
    identity: value.identity,
    bridgeURL: "http://touchcode.local:4317",
    now: () => now,
    random: (count) => Buffer.alloc(count, ++randomCall),
    signer: {
      async sign(transcript) {
        return sign("sha256", transcript, value.host.privateKey).toString("base64url");
      },
    },
  });

  const response = await manager.issue(value.request);
  deviceTrustChallengeResponseSchema.parse(response);
  const transcript = buildHostChallengeTranscript({
    purpose: "pair",
    challengeId: response.challengeId,
    hostDeviceId: value.identity.deviceId,
    clientDeviceId: value.request.clientDeviceId,
    hostPublicKeyX963: value.identity.publicKeyX963,
    clientPublicKeyX963: value.request.clientPublicKeyX963,
    hostNonce: response.hostNonce,
    clientNonce: value.request.clientNonce,
    expiresAt: response.expiresAt,
    bridgeURL: response.bridgeURL,
  });
  assert.equal(verifyP256DERSignature(value.identity.publicKeyX963, transcript, response.hostProof), true);
  assert.equal(manager.pendingCount, 1);
  const record = manager.consume(response.challengeId);
  assert.match(record.sas, /^\d{6}$/);
  assert.equal(record.transcriptDigest.length, 43);
  assert.throws(() => manager.consume(response.challengeId), (error: unknown) =>
    error instanceof HostChallengeError && error.code === "challenge_not_found");

  const expiring = await manager.issue(value.request);
  now = expiring.expiresAt;
  assert.throws(() => manager.consume(expiring.challengeId), (error: unknown) =>
    error instanceof HostChallengeError && error.code === "challenge_expired");
});

test("rejects host mismatch, reconnect, and concurrent capacity pressure", async () => {
  const value = fixture();
  let release!: () => void;
  const gate = new Promise<void>((resolve) => { release = resolve; });
  const manager = new HostChallengeManager({
    identity: value.identity,
    bridgeURL: "http://touchcode.local:4317",
    maximumPending: 1,
    random: (count) => Buffer.alloc(count, count),
    signer: {
      async sign(transcript) {
        await gate;
        return sign("sha256", transcript, value.host.privateKey).toString("base64url");
      },
    },
  });

  await assert.rejects(manager.issue({ ...value.request, hostDeviceId: value.request.clientDeviceId }), (error: unknown) =>
    error instanceof HostChallengeError && error.code === "host_identity_mismatch");
  await assert.rejects(manager.issue({
    ...value.request,
    purpose: "reconnect",
    relationshipId: "d6dba284-a902-4e41-aa04-844f569a7c9e",
  }), (error: unknown) => error instanceof HostChallengeError && error.code === "reconnect_not_available");

  const first = manager.issue(value.request);
  await assert.rejects(manager.issue(value.request), (error: unknown) =>
    error instanceof HostChallengeError && error.code === "challenge_capacity_reached");
  release();
  await first;
});

test("rejects a structurally valid proof from a different private key", async () => {
  const value = fixture();
  const other = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const manager = new HostChallengeManager({
    identity: value.identity,
    bridgeURL: "http://touchcode.local:4317",
    random: (count) => Buffer.alloc(count, count + 1),
    signer: {
      async sign(transcript) {
        return sign("sha256", transcript, other.privateKey).toString("base64url");
      },
    },
  });
  await assert.rejects(manager.issue(value.request), /does not match the advertised identity/);
  assert.equal(manager.pendingCount, 0);
});
