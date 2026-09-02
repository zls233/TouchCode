import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import test from "node:test";
import {
  deriveDeviceId,
  deviceTrustChallengeResponseSchema,
  encodeBase64URL,
  type DeviceIdentity,
  type DeviceTrustChallengeRequest,
} from "@touchcode/protocol";
import { createBridgeApp } from "../src/app.js";

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
    clientNonce: encodeBase64URL(Buffer.alloc(32, 0x44)),
  };
  return { host, identity, request };
}

test("device trust route issues pair challenges only when proof is available", async () => {
  const value = fixture();
  const legacy = await createBridgeApp({ hostIdentity: value.identity });
  const unavailable = await legacy.inject({ method: "POST", url: "/v1/device-trust/challenges", payload: value.request });
  assert.equal(unavailable.statusCode, 503);
  assert.equal(unavailable.json().error, "identity_proof_unavailable");
  await legacy.close();

  const app = await createBridgeApp({
    bridgeBaseURL: "http://touchcode.local:4317",
    hostIdentity: value.identity,
    hostIdentitySigner: {
      async sign(transcript) {
        return sign("sha256", transcript, value.host.privateKey).toString("base64url");
      },
    },
  });
  const response = await app.inject({ method: "POST", url: "/v1/device-trust/challenges", payload: value.request });
  assert.equal(response.statusCode, 201);
  const challenge = deviceTrustChallengeResponseSchema.parse(response.json());
  assert.equal(challenge.hostIdentity.deviceId, value.identity.deviceId);

  const mismatch = await app.inject({
    method: "POST",
    url: "/v1/device-trust/challenges",
    payload: { ...value.request, hostDeviceId: value.request.clientDeviceId },
  });
  assert.equal(mismatch.statusCode, 409);
  assert.equal(mismatch.json().error, "host_identity_mismatch");

  const reconnect = await app.inject({
    method: "POST",
    url: "/v1/device-trust/challenges",
    payload: {
      ...value.request,
      purpose: "reconnect",
      relationshipId: "d6dba284-a902-4e41-aa04-844f569a7c9e",
    },
  });
  assert.equal(reconnect.statusCode, 501);
  assert.equal(reconnect.json().error, "reconnect_not_available");

  const invalid = await app.inject({ method: "POST", url: "/v1/device-trust/challenges", payload: {} });
  assert.equal(invalid.statusCode, 400);
  await app.close();
});
