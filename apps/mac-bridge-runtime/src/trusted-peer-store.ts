import { mkdir, readFile, rename, writeFile, unlink } from "node:fs/promises";
import path from "node:path";
import { randomUUID } from "node:crypto";
import {
  deriveDeviceId,
  trustedPeerSchema,
  type TrustedPeer,
} from "@touchcode/protocol";

export type TrustedPeerErrorCode =
  | "peer_conflict"
  | "peer_not_found"
  | "peer_storage_failed";

export class TrustedPeerError extends Error {
  constructor(readonly code: TrustedPeerErrorCode, message?: string) {
    super(message ?? code);
  }
}

export type TrustedPeerStoreOptions = {
  filePath?: string | undefined;
  now?: () => number;
  generateRelationshipId?: () => string;
};

export class TrustedPeerStore {
  private readonly filePath: string | undefined;
  private readonly now: () => number;
  private readonly generateRelationshipId: () => string;
  private readonly peers = new Map<string, TrustedPeer>();
  private loaded = false;
  private writeChain: Promise<void> = Promise.resolve();

  constructor(options: TrustedPeerStoreOptions = {}) {
    this.filePath = options.filePath;
    this.now = options.now ?? Date.now;
    this.generateRelationshipId = options.generateRelationshipId ?? randomUUID;
  }

  async load(): Promise<void> {
    if (this.loaded) return;
    if (!this.filePath) {
      this.loaded = true;
      return;
    }
    try {
      const raw = await readFile(this.filePath, "utf8");
      const parsed = JSON.parse(raw) as unknown;
      if (!Array.isArray(parsed)) throw new Error("Trusted peers file must be an array");
      for (const entry of parsed) {
        const peer = trustedPeerSchema.parse(entry);
        this.peers.set(peer.peerDeviceId, peer);
      }
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") {
        // No file yet — treat as empty store.
      } else {
        throw new TrustedPeerError("peer_storage_failed", error instanceof Error ? error.message : String(error));
      }
    }
    this.loaded = true;
  }

  list(): TrustedPeer[] {
    this.ensureLoaded();
    return [...this.peers.values()].sort((a, b) => a.peerDeviceId.localeCompare(b.peerDeviceId));
  }

  get(peerDeviceId: string): TrustedPeer | undefined {
    this.ensureLoaded();
    return this.peers.get(peerDeviceId);
  }

  findByRelationshipId(relationshipId: string): TrustedPeer | undefined {
    this.ensureLoaded();
    for (const peer of this.peers.values()) {
      if (peer.relationshipId === relationshipId) return peer;
    }
    return undefined;
  }

  has(peerDeviceId: string): boolean {
    this.ensureLoaded();
    return this.peers.has(peerDeviceId);
  }

  async upsertFromPairing(input: {
    peerDeviceId: string;
    peerPublicKeyX963: string;
    displayName: string;
  }): Promise<TrustedPeer> {
    this.ensureLoaded();
    if (deriveDeviceId(input.peerPublicKeyX963) !== input.peerDeviceId) {
      throw new TrustedPeerError("peer_conflict", "peerDeviceId does not match peerPublicKeyX963");
    }
    const normalizedDisplayName = input.displayName.trim();
    if (!normalizedDisplayName || normalizedDisplayName.length > 128) {
      throw new TrustedPeerError("peer_conflict", "displayName must be 1-128 characters");
    }
    const existing = this.peers.get(input.peerDeviceId);
    if (existing && existing.peerPublicKeyX963 !== input.peerPublicKeyX963) {
      throw new TrustedPeerError("peer_conflict", "peerDeviceId already trusted with a different public key");
    }
    const now = this.now();
    let peer: TrustedPeer;
    if (existing) {
      peer = trustedPeerSchema.parse({
        ...existing,
        displayName: normalizedDisplayName,
        lastSeenAt: now,
      });
    } else {
      peer = trustedPeerSchema.parse({
        version: 1,
        relationshipId: this.generateRelationshipId(),
        peerDeviceId: input.peerDeviceId,
        peerPublicKeyX963: input.peerPublicKeyX963,
        displayName: normalizedDisplayName,
        firstPairedAt: now,
        lastSeenAt: now,
      });
    }
    this.peers.set(peer.peerDeviceId, peer);
    await this.persist();
    return peer;
  }

  async removeByDeviceId(peerDeviceId: string): Promise<void> {
    this.ensureLoaded();
    if (!this.peers.has(peerDeviceId)) throw new TrustedPeerError("peer_not_found");
    this.peers.delete(peerDeviceId);
    await this.persist();
  }

  async removeByRelationshipId(relationshipId: string): Promise<void> {
    this.ensureLoaded();
    let target: string | undefined;
    for (const [deviceId, peer] of this.peers) {
      if (peer.relationshipId === relationshipId) {
        target = deviceId;
        break;
      }
    }
    if (!target) throw new TrustedPeerError("peer_not_found");
    this.peers.delete(target);
    await this.persist();
  }

  async clear(): Promise<void> {
    this.ensureLoaded();
    this.peers.clear();
    await this.persist();
  }

  private ensureLoaded() {
    if (!this.loaded) throw new Error("TrustedPeerStore.load() must be called before access");
  }

  private async persist(): Promise<void> {
    if (!this.filePath) return;
    // Serialize writes to avoid interleaved temp files.
    const run = async () => {
      const directory = path.dirname(this.filePath!);
      await mkdir(directory, { recursive: true });
      const payload = JSON.stringify([...this.peers.values()], null, 2);
      const tempPath = `${this.filePath!}.tmp.${process.pid}.${Date.now()}`;
      await writeFile(tempPath, payload, "utf8");
      try {
        await rename(tempPath, this.filePath!);
      } catch (error) {
        await unlink(tempPath).catch(() => undefined);
        throw error;
      }
    };
    this.writeChain = this.writeChain.then(run, run);
    await this.writeChain;
  }
}
