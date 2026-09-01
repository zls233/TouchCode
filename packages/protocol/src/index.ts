import { z } from "zod";

export const touchCodeProtocolVersion = 1 as const;

export const touchCodeHelloSchema = z.object({
  protocolVersion: z.literal(touchCodeProtocolVersion),
  role: z.literal("host"),
  platform: z.literal("macOS"),
  appVersion: z.string().min(1),
  capabilities: z.array(z.string().min(1)),
  bridgeURL: z.string().url(),
});

export const pointSchema = z.object({
  x: z.number().min(0).max(1),
  y: z.number().min(0).max(1),
});

export const sourceReferenceSchema = z.object({
  file: z.string().min(1),
  line: z.number().int().positive(),
  column: z.number().int().nonnegative().default(0),
});

export const sourceStackFrameSchema = z.object({
  component: z.string().min(1),
  file: z.string().min(1),
  line: z.number().int().positive(),
  column: z.number().int().nonnegative().default(0),
});

export const elementSelectionSchema = z.object({
  type: z.literal("element.selection.v1"),
  eventId: z.string().min(1),
  sessionId: z.string().min(1),
  occurredAt: z.string().datetime(),
  page: z.object({
    url: z.string(),
    viewportWidth: z.number().positive(),
    viewportHeight: z.number().positive(),
    scrollX: z.number(),
    scrollY: z.number(),
    zoomScale: z.number().positive(),
  }),
  gesture: z.object({
    kind: z.enum(["tap", "circle", "arrow", "strike", "freehand"]),
    normalizedPoints: z.array(pointSchema).min(1),
  }),
  target: z.object({
    elementId: z.string().min(1),
    tag: z.string().min(1),
    role: z.string().nullable(),
    text: z.string(),
    domPath: z.string().min(1),
    rect: z.object({
      x: z.number(),
      y: z.number(),
      width: z.number().nonnegative(),
      height: z.number().nonnegative(),
    }),
    framework: z.enum(["react", "unknown"]),
    componentName: z.string().nullable(),
    source: sourceReferenceSchema.nullable(),
    sourceStack: z.array(sourceStackFrameSchema).default([]),
  }),
});

export const projectGrantRequestSchema = z.object({
  path: z.string().min(1),
});

export const codingAgentKindSchema = z.enum(["codex", "claude-code", "custom"]);

export const editIntentSchema = z.object({
  type: z.literal("edit.intent.v1"),
  intentId: z.string().min(1),
  sessionId: z.string().min(1),
  selectionEventId: z.string().min(1).optional(),
  instruction: z.string().trim().min(1).max(4_000),
  inputMode: z.enum(["text", "voice"]),
  screenshotPath: z.string().min(1).optional(),
});

export const annotationRequestSchema = z.object({
  type: z.literal("annotation.request.v1"),
  eventId: z.string().min(1),
  sessionId: z.string().min(1),
  gesture: z.object({
    kind: z.enum(["tap", "circle", "arrow", "strike", "freehand"]),
    normalizedPoints: z.array(pointSchema).min(1),
  }),
});

export const demoSessionSchema = z.object({
  sessionId: z.string().min(1),
  projectId: z.string().min(1),
  worktreePath: z.string().min(1),
  previewURL: z.string().url(),
  bridgeURL: z.string().url(),
});

const visibleElementContextSchema = z.object({
  elementId: z.string().min(1),
  tag: z.string().min(1),
  text: z.string(),
  rect: z.object({
    x: z.number(),
    y: z.number(),
    width: z.number().nonnegative(),
    height: z.number().nonnegative(),
  }),
  componentName: z.string().nullable(),
  source: sourceReferenceSchema.nullable(),
});

const visualContextSchema = z.object({
  screenshotPath: z.string().min(1),
  screenshotPaths: z.array(z.string().min(1)).min(1).max(8).optional(),
  viewportWidth: z.number().positive(),
  viewportHeight: z.number().positive(),
  elements: z.array(visibleElementContextSchema).max(100).optional(),
});

const visualViewportSchema = z.object({
  url: z.string().url(),
  width: z.number().positive(),
  height: z.number().positive(),
  scrollX: z.number().nonnegative(),
  scrollY: z.number().nonnegative(),
  zoomScale: z.number().positive(),
  devicePixelRatio: z.number().positive(),
});

const annotationBoundsSchema = z.object({
  x: z.number().nonnegative(),
  y: z.number().nonnegative(),
  width: z.number().nonnegative(),
  height: z.number().nonnegative(),
});

export const annotationCaptureSchema = z.object({
  annotatedImageBase64: z.string().min(100).max(4_000_000),
  viewport: visualViewportSchema,
  annotationBounds: annotationBoundsSchema,
  elements: z.array(visibleElementContextSchema).max(100),
});

/**
 * A single visual-edit draft may span several scroll/zoom viewports.  It is
 * intentionally atomic: the coding agent receives the complete draft rather
 * than a sequence of unrelated edits.
 */
export const visualRunRequestV2Schema = z.object({
  type: z.literal("visual.run.v2"),
  draftId: z.string().min(1),
  inputMode: z.enum(["annotation", "text", "voice"]),
  instruction: z.string().trim().min(1).max(4_000).optional(),
  captures: z.array(annotationCaptureSchema).min(1).max(8),
  provider: codingAgentKindSchema.default("codex"),
}).superRefine((value, context) => {
  if (value.inputMode !== "annotation" && !value.instruction) {
    context.addIssue({ code: z.ZodIssueCode.custom, message: "Text and voice runs require an instruction" });
  }
});

export const codingRunRequestSchema = z.object({
  projectId: z.string().min(1),
  worktreePath: z.string().min(1),
  provider: codingAgentKindSchema,
  intent: editIntentSchema,
  selection: elementSelectionSchema.optional(),
  visualContext: visualContextSchema.optional(),
}).refine((value) => value.selection || value.visualContext, {
  message: "selection or visualContext is required",
});

export const demoCodingRunRequestSchema = z.object({
  intent: editIntentSchema,
  selection: elementSelectionSchema,
  provider: codingAgentKindSchema.default("codex"),
});

export const visualCodingRunRequestSchema = z.object({
  instruction: z.string().trim().min(1).max(4_000),
  inputMode: z.enum(["text", "voice"]).default("text"),
  annotatedImageBase64: z.string().min(100).max(8_000_000),
  viewportWidth: z.number().positive(),
  viewportHeight: z.number().positive(),
  elements: z.array(visibleElementContextSchema).max(100),
  provider: codingAgentKindSchema.default("codex"),
});

export const pairSessionRequestSchema = z.object({
  pairingCode: z.string().regex(/^\d{6}$/, "Pairing code must contain six digits"),
});

export const pairedWorkspaceSessionSchema = z.object({
  sessionId: z.string().min(1),
  previewURL: z.string().url(),
  bridgeURL: z.string().url(),
  pairingCode: z.string().regex(/^\d{6}$/),
  ipadConnected: z.boolean(),
  latestRunId: z.string().min(1).nullable(),
  errorMessage: z.string().nullable(),
  clientToken: z.string().min(1),
  status: z.enum(["running", "stopped"]).default("running"),
});

export const visualEditRequestSchema = z.object({
  instruction: z.string().trim().min(1).max(4_000),
  inputMode: z.enum(["text", "voice"]).default("text"),
  annotatedImageBase64: z.string().min(100).max(8_000_000),
  viewportWidth: z.number().positive(),
  viewportHeight: z.number().positive(),
  provider: codingAgentKindSchema.default("codex"),
});

export const acceptedVisualRunRequestSchema = z.union([
  visualRunRequestV2Schema,
  visualEditRequestSchema,
]);

export const codingRunStageSchema = z.enum([
  "queued", "connecting", "reasoning", "editing", "completed", "failed",
]);
export const codingRunDecisionSchema = z.enum(["pending", "approved", "rejected"]);
export const codingRunStatusSchema = z.enum(["queued", "running", "succeeded", "failed", "cancelled"]);
export const codingRunSnapshotSchema = z.object({
  runId: z.string().min(1),
  sessionId: z.string().min(1),
  provider: codingAgentKindSchema,
  stage: codingRunStageSchema,
  status: codingRunStatusSchema,
  decision: codingRunDecisionSchema,
  message: z.string(),
  summary: z.string(),
  diff: z.string(),
  changedFiles: z.array(z.string()),
  previewRevision: z.string().min(1).nullable(),
  outcome: z.enum(["applied", "needs_clarification", "no_change", "failed"]),
  clarificationQuestion: z.string().nullable(),
  startedAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
});

export const codingRunResultSchema = z.object({
  runId: z.string().min(1),
  provider: codingAgentKindSchema,
  providerThreadId: z.string().min(1).optional(),
  status: z.enum(["succeeded", "failed", "cancelled"]),
  outcome: z.enum(["applied", "needs_clarification", "no_change", "failed"]).default("applied"),
  clarificationQuestion: z.string().nullable().default(null),
  summary: z.string(),
});

export type ElementSelection = z.infer<typeof elementSelectionSchema>;
export type ProjectGrantRequest = z.infer<typeof projectGrantRequestSchema>;
export type CodingAgentKind = z.infer<typeof codingAgentKindSchema>;
export type EditIntent = z.infer<typeof editIntentSchema>;
export type AnnotationRequest = z.infer<typeof annotationRequestSchema>;
export type DemoSession = z.infer<typeof demoSessionSchema>;
export type CodingRunRequest = z.infer<typeof codingRunRequestSchema>;
export type DemoCodingRunRequest = z.infer<typeof demoCodingRunRequestSchema>;
export type VisualCodingRunRequest = z.infer<typeof visualCodingRunRequestSchema>;
export type AnnotationCapture = z.infer<typeof annotationCaptureSchema>;
export type VisualRunRequestV2 = z.infer<typeof visualRunRequestV2Schema>;
export type AcceptedVisualRunRequest = z.infer<typeof acceptedVisualRunRequestSchema>;
export type CodingRunResult = z.infer<typeof codingRunResultSchema>;
export type CodingRunSnapshot = z.infer<typeof codingRunSnapshotSchema>;
export type TouchCodeHello = z.infer<typeof touchCodeHelloSchema>;
