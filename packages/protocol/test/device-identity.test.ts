import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  buildHostChallengeTranscript,
  deriveDeviceId,
  derivePairingSAS,
  deviceIdentityCapability,
  deviceIdentitySchema,
  devicePairConfirmationSchema,
  deviceReconnectProofSchema,
  deviceTrustChallengeRequestSchema,
  deviceTrustChallengeResponseSchema,
  deviceTrustEstablishedSchema,
  digestIdentityTranscript,
  encodeBase64URL,
  touchCodeHelloSchema,
  verifyP256DERSignature,
  type HostChallengeTranscriptInput,
} from "../src/index.js";

type GoldenFixture = {
  input: HostChallengeTranscriptInput;
  transcript: string;
  digest: string;
  sas: string;
  signature: string;
};

const fixture = JSON.parse(
  readFileSync(new URL("./fixtures/device-identity-v1.json", import.meta.url), "utf8"),
) as GoldenFixture;

const identity = {
  version: 1 as const,
  deviceId: fixture.input.hostDeviceId,
  keyAlgorithm: "p256" as const,
  signatureAlgorithm: "ecdsa-sha256" as const,
  signatureEncoding: "asn1-der" as const,
  publicKeyX963: fixture.input.hostPublicKeyX963,
  displayName: "Zhang's Mac",
};

test("legacy hello remains valid and identity hello is additive", () => {
  const legacyHello = {
    protocolVersion: 1,
    role: "host",
    platform: "macOS",
    appVersion: "0.1.0",
    capabilities: ["bonjour-discovery"],
    bridgeURL: "http://touchcode.local:8787",
  };

  assert.equal(touchCodeHelloSchema.safeParse(legacyHello).success, true);
  assert.equal(touchCodeHelloSchema.safeParse({
    ...legacyHello,
    capabilities: ["bonjour-discovery", deviceIdentityCapability],
    identity,
  }).success, true);
});

test("device identity binds the identifier to the P-256 public key", () => {
  assert.equal(deriveDeviceId(fixture.input.hostPublicKeyX963), fixture.input.hostDeviceId);
  assert.equal(deviceIdentitySchema.safeParse(identity).success, true);
  assert.equal(deviceIdentitySchema.safeParse({ ...identity, deviceId: fixture.input.clientDeviceId }).success, false);
  assert.equal(deviceIdentitySchema.safeParse({ ...identity, publicKeyX963: `${fixture.input.hostPublicKeyX963}=` }).success, false);
  assert.equal(deviceIdentitySchema.safeParse({ ...identity, publicKeyX963: encodeBase64URL(Buffer.alloc(65, 4)) }).success, false);
});

test("host challenge transcript, digest, SAS, and DER signature match the golden vector", () => {
  const transcript = buildHostChallengeTranscript(fixture.input);
  assert.equal(encodeBase64URL(transcript), fixture.transcript);
  assert.equal(digestIdentityTranscript(transcript), fixture.digest);
  assert.equal(derivePairingSAS(transcript), fixture.sas);
  assert.match(derivePairingSAS(transcript), /^\d{6}$/);
  assert.equal(verifyP256DERSignature(fixture.input.hostPublicKeyX963, transcript, fixture.signature), true);

  const tampered = Buffer.from(transcript);
  tampered[tampered.length - 1] ^= 1;
  assert.equal(verifyP256DERSignature(fixture.input.hostPublicKeyX963, tampered, fixture.signature), false);
});

test("host challenge builder rejects identity and relationship mismatches", () => {
  assert.throws(() => buildHostChallengeTranscript({
    ...fixture.input,
    hostDeviceId: fixture.input.clientDeviceId,
  }), /hostDeviceId does not match/);
  assert.throws(() => buildHostChallengeTranscript({
    ...fixture.input,
    relationshipId: "d6dba284-a902-4e41-aa04-844f569a7c9e",
  }), /must be omitted/);
  assert.throws(() => buildHostChallengeTranscript({
    ...fixture.input,
    purpose: "reconnect",
  }), /required for reconnect/);
});

test("challenge request rejects malformed encodings and enforces relationship lifecycle", () => {
  const pairRequest = {
    version: 1,
    purpose: "pair",
    hostDeviceId: fixture.input.hostDeviceId,
    clientDeviceId: fixture.input.clientDeviceId,
    clientPublicKeyX963: fixture.input.clientPublicKeyX963,
    clientDisplayName: "iPad",
    clientNonce: fixture.input.clientNonce,
  };
  assert.equal(deviceTrustChallengeRequestSchema.safeParse(pairRequest).success, true);
  assert.equal(deviceTrustChallengeRequestSchema.safeParse({ ...pairRequest, clientNonce: "AA" }).success, false);
  assert.equal(deviceTrustChallengeRequestSchema.safeParse({ ...pairRequest, relationshipId: "d6dba284-a902-4e41-aa04-844f569a7c9e" }).success, false);
  assert.equal(deviceTrustChallengeRequestSchema.safeParse({ ...pairRequest, purpose: "reconnect" }).success, false);
  assert.equal(deviceTrustChallengeRequestSchema.safeParse({
    ...pairRequest,
    purpose: "reconnect",
    relationshipId: "d6dba284-a902-4e41-aa04-844f569a7c9e",
  }).success, true);
});

test("challenge and proof schemas accept complete messages and reject unknown fields", () => {
  const relationshipId = "d6dba284-a902-4e41-aa04-844f569a7c9e";
  const sessionId = "c1dc5fae-a6d8-4454-91ea-0ec4ad735e86";
  const challenge = {
    version: 1,
    purpose: "pair",
    challengeId: fixture.input.challengeId,
    hostNonce: fixture.input.hostNonce,
    expiresAt: fixture.input.expiresAt,
    hostIdentity: identity,
    bridgeURL: fixture.input.bridgeURL,
    hostProof: fixture.signature,
  };
  assert.equal(deviceTrustChallengeResponseSchema.safeParse(challenge).success, true);
  assert.equal(deviceTrustChallengeResponseSchema.safeParse({ ...challenge, extra: true }).success, false);

  const pairConfirmation = {
    version: 1,
    challengeId: fixture.input.challengeId,
    hostChallengeDigest: fixture.digest,
    clientDeviceId: fixture.input.clientDeviceId,
    sasConfirmed: true,
    clientProof: fixture.signature,
  };
  assert.equal(devicePairConfirmationSchema.safeParse(pairConfirmation).success, true);
  assert.equal(devicePairConfirmationSchema.safeParse({ ...pairConfirmation, sasConfirmed: false }).success, false);

  assert.equal(deviceReconnectProofSchema.safeParse({
    version: 1,
    relationshipId,
    challengeId: fixture.input.challengeId,
    hostChallengeDigest: fixture.digest,
    clientDeviceId: fixture.input.clientDeviceId,
    clientProof: fixture.signature,
  }).success, true);

  assert.equal(deviceTrustEstablishedSchema.safeParse({
    version: 1,
    relationshipId,
    challengeId: fixture.input.challengeId,
    hostChallengeDigest: fixture.digest,
    hostDeviceId: fixture.input.hostDeviceId,
    clientDeviceId: fixture.input.clientDeviceId,
    sessionId,
    bridgeURL: fixture.input.bridgeURL,
    previewURL: "http://touchcode.local:5173",
    clientTokenDigest: encodeBase64URL(Buffer.alloc(32, 0x33)),
    hostProof: fixture.signature,
  }).success, true);
});
