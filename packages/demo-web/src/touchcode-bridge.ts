import { getElementBounds, getElementContext, isElementGrabbable } from "grab/primitives";

type VisibleElementContext = {
  elementId: string;
  tag: string;
  text: string;
  rect: { x: number; y: number; width: number; height: number };
  componentName: string | null;
  source: { file: string; line: number; column: number } | null;
};

const candidateSelector = [
  "button",
  "a",
  "input",
  "textarea",
  "select",
  "[role]",
  "header",
  "nav",
  "main",
  "section",
  "article",
  "aside",
  "footer",
  "h1",
  "h2",
  "h3",
  "h4",
  "h5",
  "h6",
  "p",
  "img",
  "label",
  "li",
].join(",");

function isVisibleInViewport(element: HTMLElement) {
  const rect = element.getBoundingClientRect();
  const style = getComputedStyle(element);
  return rect.width > 0
    && rect.height > 0
    && rect.bottom >= 0
    && rect.right >= 0
    && rect.top <= window.innerHeight
    && rect.left <= window.innerWidth
    && style.visibility !== "hidden"
    && style.display !== "none";
}

async function visibleContext(): Promise<VisibleElementContext[]> {
  const elements = Array.from(document.querySelectorAll<HTMLElement>(candidateSelector))
    .filter((element) => isVisibleInViewport(element) && isElementGrabbable(element))
    .slice(0, 80);

  return Promise.all(elements.map(async (element) => {
    const context = await getElementContext(element);
    const bounds = getElementBounds(element);
    return {
      elementId: context.selector || element.id || element.tagName.toLowerCase(),
      tag: element.tagName.toLowerCase(),
      text: (element.innerText || element.textContent || "").trim().slice(0, 300),
      rect: { x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height },
      componentName: context.componentName,
      source: context.filePath && context.lineNumber
        ? { file: context.filePath, line: context.lineNumber, column: context.columnNumber ?? 0 }
        : null,
    };
  }));
}

export function installTouchCodeBridge() {
  window.touchCodeBridge = { visibleContext };
}

declare global {
  interface Window {
    touchCodeBridge?: { visibleContext: () => Promise<VisibleElementContext[]> };
  }
}
