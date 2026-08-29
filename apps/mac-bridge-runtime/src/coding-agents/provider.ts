import type {
  CodingAgentKind,
  CodingRunRequest,
  CodingRunResult,
} from "@touchcode/protocol";

export type CodingRunStage =
  | "queued"
  | "connecting"
  | "reasoning"
  | "editing"
  | "completed"
  | "failed";

export type CodingRunEvent = {
  runId: string;
  provider: CodingAgentKind;
  stage: CodingRunStage;
  message: string;
};

export type CodingRunObserver = (event: CodingRunEvent) => void;

/**
 * Boundary between TouchCode Mac and an external coding agent.
 * The bridge owns transport and permissions; the provider owns code reasoning.
 */
export interface CodingAgentProvider {
  readonly kind: CodingAgentKind;
  isAvailable(): Promise<boolean>;
  run(request: CodingRunRequest, observe?: CodingRunObserver): Promise<CodingRunResult>;
}

export class CodingAgentRegistry {
  readonly #providers = new Map<CodingAgentKind, CodingAgentProvider>();

  register(provider: CodingAgentProvider) {
    this.#providers.set(provider.kind, provider);
  }

  get(kind: CodingAgentKind) {
    const provider = this.#providers.get(kind);
    if (!provider) throw new Error(`Coding agent provider is not configured: ${kind}`);
    return provider;
  }
}

