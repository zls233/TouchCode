import { randomBytes } from "node:crypto";
import {
  buildHostChallengeTranscript,
  derivePairingSAS,
  deviceTrustChallengeRequestSchema,
  deviceTrustChallengeResponseSchema,
  digestIdentityTranscript,
  encodeBase64URL,
  verifyP256DERSignature,
  type DeviceIdentity,
  type DeviceTrustChallengeRequest,
  type DeviceTrustChallengeResponse,
} from "@touchcode/protocol";
import type { HostIdentitySigner } from "./host-identity-signer.js";

export type PendingHostChallenge = {
  request: DeviceTrustChallengeRequest;
  response: DeviceTrustChallengeResponse;
  transcriptDigest: string;
  sas: string;
};

export type HostChallengeErrorCode =
  | "host_identity_mismatch"
  | "reconnect_not_available"
  | "challenge_capacity_reached"
  | "challenge_not_found"
  | "challenge_expired";

export class HostChallengeError extends Error {
  constructor(readonly code: HostChallengeErrorCode) {
    super(code);
  }
}

export type HostChallengeManagerOptions = {
  identity: DeviceIdentity;
  signer: HostIdentitySigner;
  bridgeURL: string;
  now?: () => number;
  random?: (byteCount: number) => Uint8Array;
  ttlMilliseconds?: number;
  maximumPending?: number;
};

export class HostChallengeManager {
  private readonly identity: DeviceIdentity;
  private readonly signer: HostIdentitySigner;
  private readonly bridgeURL: string;
  private readonly now: () => number;
  private readonly random: (byteCount: number) => Uint8Array;
  private readonly ttlMilliseconds: number;
  private readonly maximumPending: number;
  private readonly pending = new Map<string, PendingHostChallenge>();
  private readonly reservedIds = new Set<string>();

  constructor(options: HostChallengeManagerOptions) {
    this.identity = options.identity;
    this.signer = options.signer;
    this.bridgeURL = options.bridgeURL;
    this.now = options.now ?? Date.now;
    this.random = options.random ?? ((byteCount) => randomBytes(byteCount));
    this.ttlMilliseconds = options.ttlMilliseconds ?? 60_000;
    this.maximumPending = options.maximumPending ?? 256;
    if (this.ttlMilliseconds < 1 || this.maximumPending < 1) {
      throw new RangeError("Host challenge limits must be positive");
    }
  }

  async issue(input: DeviceTrustChallengeRequest): Promise<DeviceTrustChallengeResponse> {
    const request = deviceTrustChallengeRequestSchema.parse(input);
    if (request.hostDeviceId !== this.identity.deviceId) {
      throw new HostChallengeError("host_identity_mismatch");
    }
    if (request.purpose === "reconnect") {
      throw new HostChallengeError("reconnect_not_available");
    }

    const issuedAt = this.now();
    this.pruneExpired(issuedAt);
    if (this.pending.size + this.reservedIds.size >= this.maximumPending) {
      throw new HostChallengeError("challenge_capacity_reached");
    }
    const challengeId = this.uniqueChallengeId();
    this.reservedIds.add(challengeId);
    try {
      const hostNonce = encodeBase64URL(this.random(32));
      const expiresAt = issuedAt + this.ttlMilliseconds;
      const transcript = buildHostChallengeTranscript({
        purpose: "pair",
        challengeId,
        hostDeviceId: this.identity.deviceId,
        clientDeviceId: request.clientDeviceId,
        hostPublicKeyX963: this.identity.publicKeyX963,
        clientPublicKeyX963: request.clientPublicKeyX963,
        hostNonce,
        clientNonce: request.clientNonce,
        expiresAt,
        bridgeURL: this.bridgeURL,
      });
      const hostProof = await this.signer.sign(transcript);
      if (!verifyP256DERSignature(this.identity.publicKeyX963, transcript, hostProof)) {
        throw new Error("Host challenge proof does not match the advertised identity");
      }
      const response = deviceTrustChallengeResponseSchema.parse({
        version: 1,
        purpose: "pair",
        challengeId,
        hostNonce,
        expiresAt,
        hostIdentity: this.identity,
        bridgeURL: this.bridgeURL,
        hostProof,
      });
      this.pending.set(challengeId, {
        request,
        response,
        transcriptDigest: digestIdentityTranscript(transcript),
        sas: derivePairingSAS(transcript),
      });
      return response;
    } finally {
      this.reservedIds.delete(challengeId);
    }
  }

  consume(challengeId: string): PendingHostChallenge {
    const record = this.pending.get(challengeId);
    if (!record) throw new HostChallengeError("challenge_not_found");
    this.pending.delete(challengeId);
    if (this.now() >= record.response.expiresAt) {
      throw new HostChallengeError("challenge_expired");
    }
    return record;
  }

  get pendingCount(): number {
    this.pruneExpired(this.now());
    return this.pending.size;
  }

  private pruneExpired(now: number) {
    for (const [challengeId, record] of this.pending) {
      if (now >= record.response.expiresAt) this.pending.delete(challengeId);
    }
  }

  private uniqueChallengeId(): string {
    for (let attempt = 0; attempt < 8; attempt += 1) {
      const challengeId = encodeBase64URL(this.random(16));
      if (!this.pending.has(challengeId) && !this.reservedIds.has(challengeId)) return challengeId;
    }
    throw new HostChallengeError("challenge_capacity_reached");
  }
}
