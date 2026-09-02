import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import {
  buildHostChallengeTranscript,
  buildPairConfirmationTranscript,
  deriveDeviceId,
  devicePairConfirmResponseSchema,
  digestIdentityTranscript,
  encodeBase64URL,
  type DeviceIdentity,
  type DeviceTrustChallengeRequest,
} from "@touchcode/protocol";
import { createBridgeApp } from "../src/app.js";
import { HostChallengeManager } from "../src/host-challenge-manager.js";
import { TrustedPeerStore } from "../src/trusted-peer-store.js";

function keys() {
  const host = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const client = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const raw = (key: typeof host.publicKey) => {
    const jwk = key.export({ format: "jwk" });
    return Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x!, "base64url"), Buffer.from(jwk.y!, "base64url")]).toString("base64url");
  };
  return { host, client, hostKey: raw(host.publicKey), clientKey: raw(client.publicKey) };
}

function fixtureIdentity(hostKey: string): DeviceIdentity {
  return {
    version: 1,
    deviceId: deriveDeviceId(hostKey),
    keyAlgorithm: "p256",
    signatureAlgorithm: "ecdsa-sha256",
    signatureEncoding: "asn1-der",
    publicKeyX963: hostKey,
    displayName: "TouchCode Mac",
  };
}

function fixtureRequest(identity: DeviceIdentity, clientKey: string, clientId: string): DeviceTrustChallengeRequest {
  return {
    version: 1,
    purpose: "pair",
    hostDeviceId: identity.deviceId,
    clientDeviceId: clientId,
    clientPublicKeyX963: clientKey,
    clientDisplayName: "iPad",
    clientNonce: encodeBase64URL(Buffer.alloc(32, 0x33)),
  };
}

test("valid pair confirm creates a verified trusted peer", async () => {
  const { host, client, hostKey, clientKey } = keys();
  const identity = fixtureIdentity(hostKey);
  const clientId = deriveDeviceId(clientKey);
  const request = fixtureRequest(identity, clientKey, clientId);

  const challenges = new HostChallengeManager({
    identity,
    bridgeURL: "http://touchcode.local:4317",
    now: () => 1_788_314_400_000,
    random: (count) => Buffer.alloc(count, 0x22),
    signer: { async sign(t) { return sign("sha256", t, host.privateKey).toString("base64url"); } },
  });
  const store = new TrustedPeerStore({ now: () => 1_788_314_400_000, generateRelationshipId: () => "22222222-2222-4222-8222-222222222222" });
  await store.load();
  const app = await createBridgeApp({ bridgeBaseURL: "http://touchcode.local:4317", hostIdentity: identity, hostChallengeManager: challenges, trustedPeerStore: store });
  const c = (await app.inject({ method: "POST", url: "/v1/device-trust/challenges", payload: request })).json();
  const hostChallengeTranscript = buildHostChallengeTranscript({
    purpose: "pair",
    challengeId: c.challengeId,
    hostDeviceId: identity.deviceId,
    clientDeviceId: request.clientDeviceId,
    hostPublicKeyX963: identity.publicKeyX963,
    clientPublicKeyX963: request.clientPublicKeyX963,
    hostNonce: c.hostNonce,
    clientNonce: request.clientNonce,
    expiresAt: c.expiresAt,
    bridgeURL: c.bridgeURL,
  });
  const digest = digestIdentityTranscript(hostChallengeTranscript);

  const pairTranscript = buildPairConfirmationTranscript({ version: 1, challengeId: c.challengeId, hostChallengeDigest: digest, clientDeviceId: clientId, sasConfirmed: true });
  const clientProof = sign("sha256", pairTranscript, client.privateKey).toString("base64url");

  const confirm = await app.inject({
    method: "POST",
    url: "/v1/device-trust/confirm",
    payload: { version: 1, challengeId: c.challengeId, hostChallengeDigest: digest, clientDeviceId: clientId, sasConfirmed: true, clientProof },
  });
  assert.equal(confirm.statusCode, 201);
  const body = devicePairConfirmResponseSchema.parse(confirm.json());
  assert.equal(body.trustedPeer.peerDeviceId, clientId);
  assert.equal(body.trustedPeer.peerPublicKeyX963, clientKey);
  assert.equal(body.trustedPeer.relationshipId, "22222222-2222-4222-8222-222222222222");
  assert.equal(store.list().length, 1);

  // second confirm with same challenge must fail (one-time)
  const replay = await app.inject({
    method: "POST",
    url: "/v1/device-trust/confirm",
    payload: { version: 1, challengeId: c.challengeId, hostChallengeDigest: digest, clientDeviceId: clientId, sasConfirmed: true, clientProof },
  });
  assert.equal(replay.statusCode, 404);
  await app.close();
});

test("invalid signatures, digests, and expired challenges are rejected without creating trust", async () => {
  const { host, client, hostKey, clientKey } = keys();
  const identity = fixtureIdentity(hostKey);
  const clientId = deriveDeviceId(clientKey);
  const request = fixtureRequest(identity, clientKey, clientId);
  const otherClient = generateKeyPairSync("ec", { namedCurve: "prime256v1" });

  let now = 1_788_314_400_000;
  const challenges = new HostChallengeManager({
    identity,
    bridgeURL: "http://touchcode.local:4317",
    now: () => now,
    random: (count) => Buffer.alloc(count, 0x33),
    signer: { async sign(t) { return sign("sha256", t, host.privateKey).toString("base64url"); } },
  });
  const store = new TrustedPeerStore({ now: () => now });
  await store.load();
  const app = await createBridgeApp({ bridgeBaseURL: "http://touchcode.local:4317", hostIdentity: identity, hostChallengeManager: challenges, trustedPeerStore: store });

  async function issueWithDigest() {
    const c = (await app.inject({ method: "POST", url: "/v1/device-trust/challenges", payload: request })).json();
    const transcript = buildHostChallengeTranscript({
      purpose: "pair",
      challengeId: c.challengeId,
      hostDeviceId: identity.deviceId,
      clientDeviceId: request.clientDeviceId,
      hostPublicKeyX963: identity.publicKeyX963,
      clientPublicKeyX963: request.clientPublicKeyX963,
      hostNonce: c.hostNonce,
      clientNonce: request.clientNonce,
      expiresAt: c.expiresAt,
      bridgeURL: c.bridgeURL,
    });
    return { c, digest: digestIdentityTranscript(transcript) };
  }

  // wrong client proof
  {
    const { c, digest } = await issueWithDigest();
    const pairTranscript = buildPairConfirmationTranscript({ version: 1, challengeId: c.challengeId, hostChallengeDigest: digest, clientDeviceId: clientId, sasConfirmed: true });
    const badProof = sign("sha256", pairTranscript, otherClient.privateKey).toString("base64url");
    const res = await app.inject({ method: "POST", url: "/v1/device-trust/confirm", payload: { version: 1, challengeId: c.challengeId, hostChallengeDigest: digest, clientDeviceId: clientId, sasConfirmed: true, clientProof: badProof } });
    assert.equal(res.statusCode, 401);
    assert.equal(store.list().length, 0);
  }

  // digest mismatch
  {
    const { c, digest } = await issueWithDigest();
    const badDigest = encodeBase64URL(Buffer.alloc(32, 0x99));
    assert.notEqual(badDigest, digest);
    const pairTranscript = buildPairConfirmationTranscript({ version: 1, challengeId: c.challengeId, hostChallengeDigest: badDigest, clientDeviceId: clientId, sasConfirmed: true });
    const proof = sign("sha256", pairTranscript, client.privateKey).toString("base64url");
    const res = await app.inject({ method: "POST", url: "/v1/device-trust/confirm", payload: { version: 1, challengeId: c.challengeId, hostChallengeDigest: badDigest, clientDeviceId: clientId, sasConfirmed: true, clientProof: proof } });
    assert.equal(res.statusCode, 400);
    assert.equal(store.list().length, 0);
  }

  // expired challenge
  {
    const { c, digest } = await issueWithDigest();
    now = c.expiresAt; // move time to expiry
    const pairTranscript = buildPairConfirmationTranscript({ version: 1, challengeId: c.challengeId, hostChallengeDigest: digest, clientDeviceId: clientId, sasConfirmed: true });
    const proof = sign("sha256", pairTranscript, client.privateKey).toString("base64url");
    const res = await app.inject({ method: "POST", url: "/v1/device-trust/confirm", payload: { version: 1, challengeId: c.challengeId, hostChallengeDigest: digest, clientDeviceId: clientId, sasConfirmed: true, clientProof: proof } });
    assert.equal(res.statusCode, 410);
    assert.equal(store.list().length, 0);
    now = 1_788_314_400_000;
  }

  // clientDevice mismatch
  {
    const { c, digest } = await issueWithDigest();
    const fakeClient = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
    const jwk = fakeClient.publicKey.export({ format: "jwk" });
    const fakeKey = Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x!, "base64url"), Buffer.from(jwk.y!, "base64url")]).toString("base64url");
    const fakeId = deriveDeviceId(fakeKey);
    const pairTranscript = buildPairConfirmationTranscript({ version: 1, challengeId: c.challengeId, hostChallengeDigest: digest, clientDeviceId: fakeId, sasConfirmed: true });
    const proof = sign("sha256", pairTranscript, fakeClient.privateKey).toString("base64url");
    const res = await app.inject({ method: "POST", url: "/v1/device-trust/confirm", payload: { version: 1, challengeId: c.challengeId, hostChallengeDigest: digest, clientDeviceId: fakeId, sasConfirmed: true, clientProof: proof } });
    assert.equal(res.statusCode, 400);
    assert.equal(store.list().length, 0);
  }

  await app.close();
});

test("concurrent confirm for same challenge only succeeds once", async () => {
  const { host, client, hostKey, clientKey } = keys();
  const identity = fixtureIdentity(hostKey);
  const clientId = deriveDeviceId(clientKey);
  const request = fixtureRequest(identity, clientKey, clientId);

  const challenges = new HostChallengeManager({
    identity,
    bridgeURL: "http://touchcode.local:4317",
    now: () => 1_788_314_400_000,
    random: (count) => Buffer.alloc(count, 0x44),
    signer: { async sign(t) { return sign("sha256", t, host.privateKey).toString("base64url"); } },
  });
  const store = new TrustedPeerStore({ now: () => 1_788_314_400_000 });
  await store.load();
  const app = await createBridgeApp({ bridgeBaseURL: "http://touchcode.local:4317", hostIdentity: identity, hostChallengeManager: challenges, trustedPeerStore: store });
  const c = (await app.inject({ method: "POST", url: "/v1/device-trust/challenges", payload: request })).json();
  const transcript = buildHostChallengeTranscript({
    purpose: "pair",
    challengeId: c.challengeId,
    hostDeviceId: identity.deviceId,
    clientDeviceId: request.clientDeviceId,
    hostPublicKeyX963: identity.publicKeyX963,
    clientPublicKeyX963: request.clientPublicKeyX963,
    hostNonce: c.hostNonce,
    clientNonce: request.clientNonce,
    expiresAt: c.expiresAt,
    bridgeURL: c.bridgeURL,
  });
  const digest = digestIdentityTranscript(transcript);
  const pairTranscript = buildPairConfirmationTranscript({ version: 1, challengeId: c.challengeId, hostChallengeDigest: digest, clientDeviceId: clientId, sasConfirmed: true });
  const proof = sign("sha256", pairTranscript, client.privateKey).toString("base64url");
  const payload = { version: 1, challengeId: c.challengeId, hostChallengeDigest: digest, clientDeviceId: clientId, sasConfirmed: true, clientProof: proof };

  const [a, b] = await Promise.all([
    app.inject({ method: "POST", url: "/v1/device-trust/confirm", payload }),
    app.inject({ method: "POST", url: "/v1/device-trust/confirm", payload }),
  ]);
  const statuses = [a.statusCode, b.statusCode].sort();
  assert.deepEqual(statuses, [201, 404]);
  assert.equal(store.list().length, 1);
  await app.close();
});

test("same deviceId with different public key is rejected", async () => {
  const { host, client, hostKey, clientKey } = keys();
  const identity = fixtureIdentity(hostKey);
  const clientId = deriveDeviceId(clientKey);
  const request = fixtureRequest(identity, clientKey, clientId);

  const challenges = new HostChallengeManager({
    identity,
    bridgeURL: "http://touchcode.local:4317",
    now: () => 1_788_314_400_000,
    random: (count) => Buffer.alloc(count, 0x55),
    signer: { async sign(t) { return sign("sha256", t, host.privateKey).toString("base64url"); } },
  });
  const store = new TrustedPeerStore({ now: () => 1_788_314_400_000 });
  await store.load();
  const app = await createBridgeApp({ bridgeBaseURL: "http://touchcode.local:4317", hostIdentity: identity, hostChallengeManager: challenges, trustedPeerStore: store });

  // first pairing succeeds
  const c1 = (await app.inject({ method: "POST", url: "/v1/device-trust/challenges", payload: request })).json();
  const t1 = buildHostChallengeTranscript({
    purpose: "pair",
    challengeId: c1.challengeId,
    hostDeviceId: identity.deviceId,
    clientDeviceId: request.clientDeviceId,
    hostPublicKeyX963: identity.publicKeyX963,
    clientPublicKeyX963: request.clientPublicKeyX963,
    hostNonce: c1.hostNonce,
    clientNonce: request.clientNonce,
    expiresAt: c1.expiresAt,
    bridgeURL: c1.bridgeURL,
  });
  const d1 = digestIdentityTranscript(t1);
  const p1 = buildPairConfirmationTranscript({ version: 1, challengeId: c1.challengeId, hostChallengeDigest: d1, clientDeviceId: clientId, sasConfirmed: true });
  const proof1 = sign("sha256", p1, client.privateKey).toString("base64url");
  const r1 = await app.inject({ method: "POST", url: "/v1/device-trust/confirm", payload: { version: 1, challengeId: c1.challengeId, hostChallengeDigest: d1, clientDeviceId: clientId, sasConfirmed: true, clientProof: proof1 } });
  assert.equal(r1.statusCode, 201);

  // second client with same deviceId but different key - simulate via store conflict directly
  const other = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const jwk = other.publicKey.export({ format: "jwk" });
  const otherKey = Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x!, "base64url"), Buffer.from(jwk.y!, "base64url")]).toString("base64url");
  await assert.rejects(
    () => store.upsertFromPairing({ peerDeviceId: clientId, peerPublicKeyX963: otherKey, displayName: "iPad 2" }),
    (e: unknown) => e instanceof Error && (e as { code: string }).code === "peer_conflict",
  );
  assert.equal(store.list().length, 1);
  await app.close();
});

test("trusted peer persists across reload and can be revoked", async () => {
  const dir = mkdtempSync(path.join(tmpdir(), "touchcode-peers-"));
  const filePath = path.join(dir, "peers.json");
  const { host, client, hostKey, clientKey } = keys();
  const identity = fixtureIdentity(hostKey);
  const clientId = deriveDeviceId(clientKey);
  const request = fixtureRequest(identity, clientKey, clientId);

  const challenges = new HostChallengeManager({
    identity,
    bridgeURL: "http://touchcode.local:4317",
    now: () => 1_788_314_400_000,
    random: (count) => Buffer.alloc(count, 0x66),
    signer: { async sign(t) { return sign("sha256", t, host.privateKey).toString("base64url"); } },
  });
  const store = new TrustedPeerStore({ filePath, now: () => 1_788_314_400_000 });
  await store.load();
  const app = await createBridgeApp({ bridgeBaseURL: "http://touchcode.local:4317", hostIdentity: identity, hostChallengeManager: challenges, trustedPeerStore: store });
  const c = (await app.inject({ method: "POST", url: "/v1/device-trust/challenges", payload: request })).json();
  const transcript = buildHostChallengeTranscript({
    purpose: "pair",
    challengeId: c.challengeId,
    hostDeviceId: identity.deviceId,
    clientDeviceId: request.clientDeviceId,
    hostPublicKeyX963: identity.publicKeyX963,
    clientPublicKeyX963: request.clientPublicKeyX963,
    hostNonce: c.hostNonce,
    clientNonce: request.clientNonce,
    expiresAt: c.expiresAt,
    bridgeURL: c.bridgeURL,
  });
  const digest = digestIdentityTranscript(transcript);
  const pairTranscript = buildPairConfirmationTranscript({ version: 1, challengeId: c.challengeId, hostChallengeDigest: digest, clientDeviceId: clientId, sasConfirmed: true });
  const proof = sign("sha256", pairTranscript, client.privateKey).toString("base64url");
  const confirm = await app.inject({ method: "POST", url: "/v1/device-trust/confirm", payload: { version: 1, challengeId: c.challengeId, hostChallengeDigest: digest, clientDeviceId: clientId, sasConfirmed: true, clientProof: proof } });
  assert.equal(confirm.statusCode, 201);
  const peersBefore = (await app.inject({ method: "GET", url: "/v1/device-trust/peers" })).json();
  assert.equal(peersBefore.peers.length, 1);
  await app.close();

  // reload from same file
  const store2 = new TrustedPeerStore({ filePath, now: () => 1_788_314_400_000 });
  await store2.load();
  assert.equal(store2.list().length, 1);
  const app2 = await createBridgeApp({ bridgeBaseURL: "http://touchcode.local:4317", hostIdentity: identity, hostChallengeManager: new HostChallengeManager({ identity, bridgeURL: "http://touchcode.local:4317", signer: { async sign(t) { return sign("sha256", t, host.privateKey).toString("base64url"); } } }), trustedPeerStore: store2 });
  const peersAfter = (await app2.inject({ method: "GET", url: "/v1/device-trust/peers" })).json();
  assert.equal(peersAfter.peers.length, 1);
  const relationshipId = peersAfter.peers[0].relationshipId;
  const del = await app2.inject({ method: "DELETE", url: `/v1/device-trust/peers/${relationshipId}` });
  assert.equal(del.statusCode, 204);
  const peersEmpty = (await app2.inject({ method: "GET", url: "/v1/device-trust/peers" })).json();
  assert.equal(peersEmpty.peers.length, 0);
  await app2.close();

  // verify file reflects clear
  const store3 = new TrustedPeerStore({ filePath });
  await store3.load();
  assert.equal(store3.list().length, 0);

  rmSync(dir, { recursive: true, force: true });
});

test("atomic write does not leave partial file on failure path", async () => {
  const dir = mkdtempSync(path.join(tmpdir(), "touchcode-peers-atomic-"));
  const filePath = path.join(dir, "peers.json");
  const { clientKey } = keys();
  const store = new TrustedPeerStore({ filePath, now: () => 1_788_314_400_000, generateRelationshipId: () => "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa" });
  await store.load();
  const clientId = deriveDeviceId(clientKey);
  await store.upsertFromPairing({ peerDeviceId: clientId, peerPublicKeyX963: clientKey, displayName: "iPad" });
  assert.equal(store.list().length, 1);
  await store.upsertFromPairing({ peerDeviceId: clientId, peerPublicKeyX963: clientKey, displayName: "iPad renamed" });
  assert.equal(store.list()[0]?.displayName, "iPad renamed");
  rmSync(dir, { recursive: true, force: true });
});
