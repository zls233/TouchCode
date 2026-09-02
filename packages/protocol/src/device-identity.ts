import { createHash, createPublicKey, verify } from "node:crypto";
import { z } from "zod";

const DEVICE_ID_DOMAIN = Buffer.from("TouchCode device id v1\0p256\0", "utf8");
const TRANSCRIPT_DOMAIN = Buffer.from("TouchCode Identity v1\0", "utf8");
const SAS_DOMAIN = Buffer.from("TouchCode pairing SAS v1\0", "utf8");

export const deviceIdentityCapability = "device-identity-v1" as const;

function isCanonicalBase64URL(value: string): boolean {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) return false;
  try {
    return Buffer.from(value, "base64url").toString("base64url") === value;
  } catch {
    return false;
  }
}

function hasDecodedLength(value: string, expectedLength: number): boolean {
  return isCanonicalBase64URL(value) && Buffer.from(value, "base64url").length === expectedLength;
}

function isCanonicalP256PublicKey(value: string): boolean {
  if (!hasDecodedLength(value, 65)) return false;
  const point = Buffer.from(value, "base64url");
  if (point[0] !== 0x04) return false;
  try {
    createPublicKey({
      key: {
        kty: "EC",
        crv: "P-256",
        x: point.subarray(1, 33).toString("base64url"),
        y: point.subarray(33, 65).toString("base64url"),
      },
      format: "jwk",
    });
    return true;
  } catch {
    return false;
  }
}

function isCanonicalDERSignature(value: string): boolean {
  if (!isCanonicalBase64URL(value)) return false;
  const bytes = Buffer.from(value, "base64url");
  if (bytes.length < 8 || bytes.length > 72 || bytes[0] !== 0x30 || bytes[1] !== bytes.length - 2) return false;

  let offset = 2;
  for (let component = 0; component < 2; component += 1) {
    if (bytes[offset] !== 0x02) return false;
    const length = bytes[offset + 1];
    if (length === undefined) return false;
    offset += 2;
    if (length < 1 || length > 33 || offset + length > bytes.length) return false;
    const first = bytes[offset];
    if (first === undefined) return false;
    if ((first & 0x80) !== 0) return false;
    const second = bytes[offset + 1];
    if (length > 1 && first === 0x00 && second !== undefined && (second & 0x80) === 0) return false;
    offset += length;
  }
  return offset === bytes.length;
}

export const canonicalBase64URLSchema = z.string().refine(isCanonicalBase64URL, {
  message: "Expected canonical unpadded base64url",
});

export const p256PublicKeyX963Schema = z.string().refine(isCanonicalP256PublicKey, {
  message: "Expected a 65-byte uncompressed P-256 X9.63 public key",
});

export const ecdsaP256DERSignatureSchema = z.string().refine(isCanonicalDERSignature, {
  message: "Expected a canonical ASN.1 DER ECDSA signature",
});

export const nonce256Schema = z.string().refine((value) => hasDecodedLength(value, 32), {
  message: "Expected a 32-byte nonce encoded as canonical base64url",
});

export const sha256DigestSchema = z.string().refine((value) => hasDecodedLength(value, 32), {
  message: "Expected a SHA-256 digest encoded as canonical base64url",
});

export const challengeIdSchema = z.string().refine((value) => {
  if (!isCanonicalBase64URL(value)) return false;
  const length = Buffer.from(value, "base64url").length;
  return length >= 16 && length <= 64;
}, { message: "Expected a 16-64 byte challenge identifier encoded as canonical base64url" });

export const deviceIdSchema = z.string().regex(/^tcid1_[A-Za-z0-9_-]{43}$/);

export function encodeBase64URL(value: Uint8Array): string {
  return Buffer.from(value).toString("base64url");
}

function decode(value: string): Buffer {
  return Buffer.from(value, "base64url");
}

export function deriveDeviceId(publicKeyX963: string): string {
  const parsedKey = p256PublicKeyX963Schema.parse(publicKeyX963);
  const digest = createHash("sha256").update(DEVICE_ID_DOMAIN).update(decode(parsedKey)).digest();
  return `tcid1_${encodeBase64URL(digest)}`;
}

export const deviceIdentitySchema = z.object({
  version: z.literal(1),
  deviceId: deviceIdSchema,
  keyAlgorithm: z.literal("p256"),
  signatureAlgorithm: z.literal("ecdsa-sha256"),
  signatureEncoding: z.literal("asn1-der"),
  publicKeyX963: p256PublicKeyX963Schema,
  displayName: z.string().trim().min(1).max(128),
}).strict().superRefine((identity, context) => {
  const parsedKey = p256PublicKeyX963Schema.safeParse(identity.publicKeyX963);
  if (parsedKey.success && deriveDeviceId(parsedKey.data) !== identity.deviceId) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["deviceId"],
      message: "deviceId does not match publicKeyX963",
    });
  }
});

const relationshipIdSchema = z.string().uuid();
const epochMillisSchema = z.number().int().nonnegative().safe();
const httpURLSchema = z.string().url().refine((value) => {
  const protocol = new URL(value).protocol;
  return protocol === "http:" || protocol === "https:";
}, "Expected an HTTP(S) URL");

export const deviceTrustChallengeRequestSchema = z.object({
  version: z.literal(1),
  purpose: z.enum(["pair", "reconnect"]),
  hostDeviceId: deviceIdSchema,
  clientDeviceId: deviceIdSchema,
  clientPublicKeyX963: p256PublicKeyX963Schema,
  clientDisplayName: z.string().trim().min(1).max(128),
  relationshipId: relationshipIdSchema.optional(),
  clientNonce: nonce256Schema,
}).strict().superRefine((request, context) => {
  const parsedKey = p256PublicKeyX963Schema.safeParse(request.clientPublicKeyX963);
  if (parsedKey.success && deriveDeviceId(parsedKey.data) !== request.clientDeviceId) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["clientDeviceId"],
      message: "clientDeviceId does not match clientPublicKeyX963",
    });
  }
  if (request.purpose === "reconnect" && request.relationshipId === undefined) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["relationshipId"],
      message: "relationshipId is required for reconnect",
    });
  }
  if (request.purpose === "pair" && request.relationshipId !== undefined) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["relationshipId"],
      message: "relationshipId must be omitted for initial pairing",
    });
  }
});

export const deviceTrustChallengeResponseSchema = z.object({
  version: z.literal(1),
  purpose: z.enum(["pair", "reconnect"]),
  challengeId: challengeIdSchema,
  relationshipId: relationshipIdSchema.optional(),
  hostNonce: nonce256Schema,
  expiresAt: epochMillisSchema,
  hostIdentity: deviceIdentitySchema,
  bridgeURL: httpURLSchema,
  hostProof: ecdsaP256DERSignatureSchema,
}).strict().superRefine((response, context) => {
  if (response.purpose === "reconnect" && response.relationshipId === undefined) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ["relationshipId"], message: "relationshipId is required for reconnect" });
  }
  if (response.purpose === "pair" && response.relationshipId !== undefined) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ["relationshipId"], message: "relationshipId must be omitted for initial pairing" });
  }
});

export const devicePairConfirmationSchema = z.object({
  version: z.literal(1),
  challengeId: challengeIdSchema,
  hostChallengeDigest: sha256DigestSchema,
  clientDeviceId: deviceIdSchema,
  sasConfirmed: z.literal(true),
  clientProof: ecdsaP256DERSignatureSchema,
}).strict();

export const deviceReconnectProofSchema = z.object({
  version: z.literal(1),
  relationshipId: relationshipIdSchema,
  challengeId: challengeIdSchema,
  hostChallengeDigest: sha256DigestSchema,
  clientDeviceId: deviceIdSchema,
  clientProof: ecdsaP256DERSignatureSchema,
}).strict();

export const deviceTrustEstablishedSchema = z.object({
  version: z.literal(1),
  relationshipId: relationshipIdSchema,
  challengeId: challengeIdSchema,
  hostChallengeDigest: sha256DigestSchema,
  hostDeviceId: deviceIdSchema,
  clientDeviceId: deviceIdSchema,
  sessionId: z.string().uuid(),
  bridgeURL: httpURLSchema,
  previewURL: httpURLSchema,
  clientTokenDigest: sha256DigestSchema,
  hostProof: ecdsaP256DERSignatureSchema,
}).strict();

export const deviceIdentityMessageType = {
  hostChallenge: 1,
  pairConfirmation: 2,
  reconnectProof: 3,
  trustEstablished: 4,
} as const;

export type DeviceIdentity = z.infer<typeof deviceIdentitySchema>;
export type DeviceTrustChallengeRequest = z.infer<typeof deviceTrustChallengeRequestSchema>;
export type DeviceTrustChallengeResponse = z.infer<typeof deviceTrustChallengeResponseSchema>;
export type DevicePairConfirmation = z.infer<typeof devicePairConfirmationSchema>;
export type DeviceReconnectProof = z.infer<typeof deviceReconnectProofSchema>;
export type DeviceTrustEstablished = z.infer<typeof deviceTrustEstablishedSchema>;

export type HostChallengeTranscriptInput = {
  purpose: "pair" | "reconnect";
  challengeId: string;
  hostDeviceId: string;
  clientDeviceId: string;
  hostPublicKeyX963: string;
  clientPublicKeyX963: string;
  hostNonce: string;
  clientNonce: string;
  relationshipId?: string;
  expiresAt: number;
  bridgeURL: string;
};

function utf8(value: string): Buffer {
  return Buffer.from(value, "utf8");
}

function uint64(value: number): Buffer {
  if (!Number.isSafeInteger(value) || value < 0) throw new RangeError("Expected a non-negative safe integer");
  const bytes = Buffer.alloc(8);
  bytes.writeBigUInt64BE(BigInt(value));
  return bytes;
}

function sha256(value: Uint8Array): Buffer {
  return createHash("sha256").update(value).digest();
}

export function buildIdentityTranscript(messageType: number, fields: readonly Uint8Array[]): Buffer {
  if (!Number.isInteger(messageType) || messageType < 1 || messageType > 255) {
    throw new RangeError("messageType must be an integer from 1 through 255");
  }
  const encodedFields = fields.map((field) => {
    const bytes = Buffer.from(field);
    const length = Buffer.alloc(4);
    length.writeUInt32BE(bytes.length);
    return Buffer.concat([length, bytes]);
  });
  return Buffer.concat([TRANSCRIPT_DOMAIN, Buffer.from([messageType]), ...encodedFields]);
}

export function buildHostChallengeTranscript(input: HostChallengeTranscriptInput): Buffer {
  const purpose = z.enum(["pair", "reconnect"]).parse(input.purpose);
  deviceIdSchema.parse(input.hostDeviceId);
  deviceIdSchema.parse(input.clientDeviceId);
  const hostKey = p256PublicKeyX963Schema.parse(input.hostPublicKeyX963);
  const clientKey = p256PublicKeyX963Schema.parse(input.clientPublicKeyX963);
  const hostNonce = nonce256Schema.parse(input.hostNonce);
  const clientNonce = nonce256Schema.parse(input.clientNonce);
  challengeIdSchema.parse(input.challengeId);
  httpURLSchema.parse(input.bridgeURL);
  if (input.relationshipId !== undefined) relationshipIdSchema.parse(input.relationshipId);
  if (purpose === "pair" && input.relationshipId !== undefined) {
    throw new TypeError("relationshipId must be omitted for initial pairing");
  }
  if (purpose === "reconnect" && input.relationshipId === undefined) {
    throw new TypeError("relationshipId is required for reconnect");
  }
  if (deriveDeviceId(hostKey) !== input.hostDeviceId) {
    throw new TypeError("hostDeviceId does not match hostPublicKeyX963");
  }
  if (deriveDeviceId(clientKey) !== input.clientDeviceId) {
    throw new TypeError("clientDeviceId does not match clientPublicKeyX963");
  }

  return buildIdentityTranscript(deviceIdentityMessageType.hostChallenge, [
    Buffer.from([1]),
    utf8(purpose),
    decode(input.challengeId),
    utf8(input.hostDeviceId),
    utf8(input.clientDeviceId),
    sha256(decode(hostKey)),
    sha256(decode(clientKey)),
    decode(hostNonce),
    decode(clientNonce),
    utf8(input.relationshipId ?? ""),
    uint64(input.expiresAt),
    utf8(input.bridgeURL),
  ]);
}

export function buildPairConfirmationTranscript(input: Omit<DevicePairConfirmation, "clientProof">): Buffer {
  const parsed = devicePairConfirmationSchema.omit({ clientProof: true }).parse(input);
  return buildIdentityTranscript(deviceIdentityMessageType.pairConfirmation, [
    Buffer.from([1]), decode(parsed.challengeId), decode(parsed.hostChallengeDigest), utf8(parsed.clientDeviceId), Buffer.from([1]),
  ]);
}

export function buildReconnectProofTranscript(input: Omit<DeviceReconnectProof, "clientProof">): Buffer {
  const parsed = deviceReconnectProofSchema.omit({ clientProof: true }).parse(input);
  return buildIdentityTranscript(deviceIdentityMessageType.reconnectProof, [
    Buffer.from([1]), utf8(parsed.relationshipId), decode(parsed.challengeId), decode(parsed.hostChallengeDigest), utf8(parsed.clientDeviceId),
  ]);
}

export function buildTrustEstablishedTranscript(input: Omit<DeviceTrustEstablished, "hostProof">): Buffer {
  const parsed = deviceTrustEstablishedSchema.omit({ hostProof: true }).parse(input);
  return buildIdentityTranscript(deviceIdentityMessageType.trustEstablished, [
    Buffer.from([1]),
    utf8(parsed.relationshipId),
    decode(parsed.challengeId),
    decode(parsed.hostChallengeDigest),
    utf8(parsed.hostDeviceId),
    utf8(parsed.clientDeviceId),
    utf8(parsed.sessionId),
    utf8(parsed.bridgeURL),
    utf8(parsed.previewURL),
    decode(parsed.clientTokenDigest),
  ]);
}

export function digestIdentityTranscript(transcript: Uint8Array): string {
  return encodeBase64URL(sha256(transcript));
}

export function derivePairingSAS(hostChallengeTranscript: Uint8Array): string {
  const digest = createHash("sha256").update(SAS_DOMAIN).update(hostChallengeTranscript).digest();
  return (digest.readUInt32BE(0) % 1_000_000).toString().padStart(6, "0");
}

export function verifyP256DERSignature(publicKeyX963: string, transcript: Uint8Array, signature: string): boolean {
  const point = decode(p256PublicKeyX963Schema.parse(publicKeyX963));
  const parsedSignature = ecdsaP256DERSignatureSchema.parse(signature);
  const key = createPublicKey({
    key: {
      kty: "EC",
      crv: "P-256",
      x: encodeBase64URL(point.subarray(1, 33)),
      y: encodeBase64URL(point.subarray(33, 65)),
    },
    format: "jwk",
  });
  return verify("sha256", transcript, key, decode(parsedSignature));
}
