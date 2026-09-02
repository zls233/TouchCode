import { z } from "zod";

// Framing limits — shared between Bridge (Node) and iPad (Swift) to avoid
// over-allocation before parsing. Keep stricter than HTTP bodyLimit.
export const transportFrameLimits = {
  maxHelloBytes: 64 * 1024,
  maxEnvelopeBytes: 1 * 1024 * 1024, // 1 MiB
  maxPayloadBytes: 1 * 1024 * 1024,
  heartbeatIntervalMs: 30_000,
  heartbeatTimeoutMs: 90_000,
  maxReconnectDelayMs: 30_000,
  initialReconnectDelayMs: 500,
} as const;

export const transportMessageKindSchema = z.enum([
  "hello",
  "heartbeat.ping",
  "heartbeat.pong",
  "session",
  "workspace",
  "codex",
  "preview",
  "annotation",
  "voice",
  "viewport",
  "file",
  "error",
]);

export const touchCodeEnvelopeSchema = z.object({
  version: z.literal(1),
  id: z.string().uuid(),
  kind: transportMessageKindSchema,
  payload: z.unknown(),
  sentAt: z.number().int().nonnegative().safe().optional(),
}).strict().superRefine((env, ctx) => {
  // Rough size guard: JSON stringified length must fit maxEnvelopeBytes.
  // Exact byte limit is enforced at transport framing layer before parse.
  const json = JSON.stringify(env.payload);
  if (json.length > transportFrameLimits.maxPayloadBytes) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, message: "payload exceeds maxPayloadBytes" });
  }
});

export const heartbeatPingSchema = z.object({
  version: z.literal(1),
  kind: z.literal("heartbeat.ping"),
  id: z.string().uuid(),
  sentAt: z.number().int().nonnegative().safe(),
}).strict();

export const heartbeatPongSchema = z.object({
  version: z.literal(1),
  kind: z.literal("heartbeat.pong"),
  id: z.string().uuid(),
  sentAt: z.number().int().nonnegative().safe(),
  replyTo: z.string().uuid(),
}).strict();

export type TransportMessageKind = z.infer<typeof transportMessageKindSchema>;
export type TouchCodeEnvelope = z.infer<typeof touchCodeEnvelopeSchema>;
export type HeartbeatPing = z.infer<typeof heartbeatPingSchema>;
export type HeartbeatPong = z.infer<typeof heartbeatPongSchema>;

export function nextReconnectDelay(attempt: number): number {
  if (attempt < 0) throw new RangeError("attempt must be non-negative");
  // Exponential backoff: 500ms * 2^attempt, capped at 30s, with jitter handled by caller if needed.
  const delay = transportFrameLimits.initialReconnectDelayMs * Math.pow(2, attempt);
  return Math.min(delay, transportFrameLimits.maxReconnectDelayMs);
}

export function validateHelloBytes(data: Uint8Array): void {
  if (data.byteLength > transportFrameLimits.maxHelloBytes) {
    throw new RangeError(`hello exceeds maxHelloBytes ${transportFrameLimits.maxHelloBytes}`);
  }
}

export function validateEnvelopeBytes(data: Uint8Array): void {
  if (data.byteLength > transportFrameLimits.maxEnvelopeBytes) {
    throw new RangeError(`envelope exceeds maxEnvelopeBytes ${transportFrameLimits.maxEnvelopeBytes}`);
  }
}
