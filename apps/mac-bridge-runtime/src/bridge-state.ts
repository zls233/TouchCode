import type { ElementSelection } from "@touchcode/protocol";

export class BridgeState {
  readonly #selections = new Map<string, ElementSelection>();

  acceptSelection(selection: ElementSelection) {
    const duplicate = this.#selections.has(selection.eventId);
    this.#selections.set(selection.eventId, selection);
    if (this.#selections.size > 100) {
      const oldest = this.#selections.keys().next().value;
      if (oldest) this.#selections.delete(oldest);
    }
    return { accepted: true, duplicate };
  }

  getSelection(eventId: string) {
    return this.#selections.get(eventId);
  }

  listSelections() {
    return [...this.#selections.values()];
  }
}

