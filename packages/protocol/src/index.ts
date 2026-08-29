import { z } from "zod";

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
  selectionEventId: z.string().min(1),
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
  viewportWidth: z.number().positive(),
  viewportHeight: z.number().positive(),
  elements: z.array(visibleElementContextSchema).max(100),
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

export const codingRunResultSchema = z.object({
  runId: z.string().min(1),
  provider: codingAgentKindSchema,
  providerThreadId: z.string().min(1).optional(),
  status: z.enum(["succeeded", "failed", "cancelled"]),
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
export type CodingRunResult = z.infer<typeof codingRunResultSchema>;
