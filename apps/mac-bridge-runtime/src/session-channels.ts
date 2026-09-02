export type ChannelKind = "control" | "codex" | "preview" | "file" | "voice" | "annotation";

export type SessionMessage = {
  id: string;
  channel: ChannelKind;
  payload: Uint8Array;
  sentAt: number;
};

export const channelPriorities: Record<ChannelKind, number> = {
  control: 0,
  codex: 1,
  voice: 1,
  annotation: 2,
  preview: 3,
  file: 4,
};

export const maxPayloadBytes = 1 * 1024 * 1024;
export const fileChunkBytes = 64 * 1024;

export class ChannelMultiplexer {
  private readonly queues = new Map<ChannelKind, SessionMessage[]>();
  private readonly waiters = new Map<ChannelKind, ((msg: SessionMessage) => void)[]>();

  constructor() {
    for (const kind of ["control", "codex", "preview", "file", "voice", "annotation"] as ChannelKind[]) {
      this.queues.set(kind, []);
      this.waiters.set(kind, []);
    }
  }

  async send(message: SessionMessage): Promise<void> {
    if (message.payload.byteLength > maxPayloadBytes) {
      throw new Error("payloadTooLarge");
    }
    if (message.channel === "file" && message.payload.byteLength > fileChunkBytes) {
      for (let offset = 0; offset < message.payload.byteLength; offset += fileChunkBytes) {
        const chunk = message.payload.subarray(offset, Math.min(offset + fileChunkBytes, message.payload.byteLength));
        const chunkMsg: SessionMessage = { ...message, payload: chunk };
        await this.enqueue(chunkMsg);
        // Yield to allow control messages to interleave
        await new Promise<void>((r) => setTimeout(r, 0));
      }
      return;
    }
    await this.enqueue(message);
  }

  private async enqueue(message: SessionMessage): Promise<void> {
    const waiters = this.waiters.get(message.channel);
    if (waiters && waiters.length > 0) {
      const waiter = waiters.shift()!;
      waiter(message);
      return;
    }
    const q = this.queues.get(message.channel);
    if (q) q.push(message);
  }

  async receive(channel: ChannelKind): Promise<SessionMessage> {
    const q = this.queues.get(channel);
    if (q && q.length > 0) return q.shift()!;
    return new Promise<SessionMessage>((resolve) => {
      const w = this.waiters.get(channel);
      if (w) w.push(resolve);
      else this.waiters.set(channel, [resolve]);
    });
  }

  tryReceive(channel: ChannelKind): SessionMessage | undefined {
    const q = this.queues.get(channel);
    if (q && q.length > 0) return q.shift()!;
    return undefined;
  }

  close() {
    for (const w of this.waiters.values()) {
      for (const waiter of w) {
        // No-op: waiters will hang, but for tests we clear
      }
    }
    this.waiters.clear();
    this.queues.clear();
  }
}
