import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import "./styles.css";

declare global {
  interface Window {
    webkit?: { messageHandlers?: { touchCodePreview?: { postMessage(value: unknown): void } } };
  }
  interface ImportMeta {
    hot?: { on(event: string, callback: () => void): void };
  }
}

async function fetchPreciseRevision(): Promise<string | null> {
  try {
    const res = await fetch("/__touchcode_preview_revision.json", { cache: "no-store" });
    if (!res.ok) return null;
    const data = (await res.json()) as { revision?: string | number };
    if (data.revision == null) return null;
    return String(data.revision);
  } catch {
    return null;
  }
}

async function notifyPreviewRevision() {
  const key = "touchcode.previewRevision";
  const precise = await fetchPreciseRevision();
  if (precise != null) {
    // Sync local monotonic counter to server-precise revision to avoid drift from manual HMRs.
    window.sessionStorage.setItem(key, precise);
    const numeric = Number(precise);
    window.webkit?.messageHandlers?.touchCodePreview?.postMessage({
      revision: Number.isFinite(numeric) ? numeric : precise,
    });
    return;
  }
  const revision = (Number(window.sessionStorage.getItem(key) ?? "0") || 0) + 1;
  window.sessionStorage.setItem(key, String(revision));
  window.webkit?.messageHandlers?.touchCodePreview?.postMessage({
    revision,
  });
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);

void notifyPreviewRevision();

if (import.meta.hot) {
  import.meta.hot.on("vite:afterUpdate", () => void notifyPreviewRevision());
}
