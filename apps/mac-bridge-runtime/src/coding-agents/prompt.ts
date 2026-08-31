import type { CodingRunRequest } from "@touchcode/protocol";

export function buildCodingPrompt(request: CodingRunRequest) {
  const visualContext = request.visualContext;
  if (!visualContext) throw new Error("Visual context is required for a coding run");
  return [
    "You are the coding agent selected by the user through TouchCode.",
    "The attached image is the current webpage with the user's raw Apple Pencil marks composited on top.",
    "Interpret the marks visually together with the user's typed or speech-transcribed instruction.",
    "There is deliberately no DOM, component, selector, or source-location metadata.",
    "Inspect the current workspace and make the smallest source-code change that satisfies the request.",
    "Do not modify files outside the workspace or install dependencies.",
    "Do not edit the attached screenshot; edit the webpage source code.",
    "If the requested change is ambiguous, do not edit files. Ask one concise clarification question.",
    "End with exactly one JSON object on its own line: {\"outcome\":\"applied|needs_clarification|no_change\",\"summary\":\"...\",\"clarificationQuestion\":null|string}.",
    "",
    `User request: ${request.intent.instruction}`,
    `Input mode: ${request.intent.inputMode}`,
    `Screenshot viewport: ${visualContext.viewportWidth} x ${visualContext.viewportHeight}`,
    visualContext.screenshotPaths && visualContext.screenshotPaths.length > 1
      ? `The request contains ${visualContext.screenshotPaths.length} related scroll/zoom captures; consider all of them before editing.`
      : "",
  ].join("\n");
}
