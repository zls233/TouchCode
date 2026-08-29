import type { CodingRunRequest } from "@touchcode/protocol";

export function buildCodingPrompt(request: CodingRunRequest) {
  const { intent, selection, visualContext } = request;

  if (visualContext) {
    return [
      "You are the coding agent selected by the user through TouchCode.",
      "The attached image is a live webpage screenshot with the user's raw Apple Pencil marks composited on top.",
      "Interpret the marks visually together with the text request. Do not assume a hard-coded circle, arrow, or strike gesture rule.",
      "The visible DOM/React candidates below are supporting evidence. Their rectangles use the screenshot viewport coordinate space.",
      "Inspect the current workspace and make the smallest source-code change that satisfies the request.",
      "Do not modify files outside the workspace, install dependencies, or edit .touchcode-inputs.",
      "Do not run broad checks; summarize the source files changed and what changed.",
      "",
      `User request: ${intent.instruction}`,
      `Viewport: ${visualContext.viewportWidth} x ${visualContext.viewportHeight}`,
      "Visible element candidates:",
      JSON.stringify(visualContext.elements, null, 2),
    ].join("\n");
  }

  if (!selection) throw new Error("A visual context or element selection is required");
  const source = selection.target.source;
  const sourceDescription = source
    ? `${source.file}:${source.line}:${source.column}`
    : "Source location unavailable; inspect the DOM context and project before editing.";

  return [
    "You are the coding agent selected by the user through TouchCode.",
    "Make the smallest change that satisfies the request in the current workspace.",
    "Do not modify files outside the workspace or install dependencies.",
    "Do not run broad checks; summarize the source files changed and what changed.",
    "",
    `User request: ${intent.instruction}`,
    `Selected element: <${selection.target.tag}> ${selection.target.text}`,
    `React component: ${selection.target.componentName ?? "unknown"}`,
    `Source: ${sourceDescription}`,
    `DOM path: ${selection.target.domPath}`,
  ].join("\n");
}
