import assert from "node:assert/strict";
import test from "node:test";

// Mirrors Swift AnnotationViewportKey.isNearlyEqual
type ViewportKey = { url: string; width: number; height: number; scrollX: number; scrollY: number; zoomScale: number };

function isNearlyEqual(a: ViewportKey, b: ViewportKey, scrollTolerance = 0.5, zoomTolerance = 0.02, sizeTolerance = 0.5): boolean {
  return (
    a.url === b.url &&
    Math.abs(a.width - b.width) < sizeTolerance &&
    Math.abs(a.height - b.height) < sizeTolerance &&
    Math.abs(a.scrollX - b.scrollX) < scrollTolerance &&
    Math.abs(a.scrollY - b.scrollY) < scrollTolerance &&
    Math.abs(a.zoomScale - b.zoomScale) < zoomTolerance
  );
}

function quantizedViewportKey(width: number, height: number, scrollX: number, scrollY: number, zoomScale: number, url: string): ViewportKey {
  // Mirrors ReadyViewportFrame quantization: width*10, scale*100, pageLeft*10
  return {
    url: new URL(url).origin,
    width: Math.round(width * 10) / 10,
    height: Math.round(height * 10) / 10,
    scrollX: Math.round(scrollX * 10) / 10,
    scrollY: Math.round(scrollY * 10) / 10,
    zoomScale: Math.round(zoomScale * 100) / 100,
  };
}

// Budget helper mirrors bridge persistCaptures totalBytes check and iPad adaptive compression targeting
function totalDecodedBytes(base64Strings: string[]): number {
  return base64Strings.reduce((sum, b64) => sum + Buffer.byteLength(b64, "base64"), 0);
}

function wouldExceedBudget(base64Strings: string[], budget = 12 * 1024 * 1024): boolean {
  return totalDecodedBytes(base64Strings) > budget;
}

function adaptiveTargetPerCapture(count: number, budget = 12 * 1024 * 1024, perCaptureLimit = 3 * 1024 * 1024): number {
  return Math.min(perCaptureLimit, Math.floor(budget / Math.max(count, 1)));
}

test("viewport quantization coalesces micro jitter", () => {
  const a = quantizedViewportKey(1024, 768, 10.04, 20.04, 1.0, "http://127.0.0.1:5173/page");
  const b = quantizedViewportKey(1024, 768, 10.06, 20.06, 1.0, "http://127.0.0.1:5173/page");
  // 10.04*10=100.4→100→10.0, 10.06*10=100.6→101→10.1 => quantized differs by 0.1, but isNearlyEqual with 0.5 should coalesce
  assert.equal(a.width, 1024);
  assert.equal(isNearlyEqual(a, b), true, "0.02 jitter should be nearly equal with 0.5 tolerance");
});

test("viewport isNearlyEqual rejects intentional scroll", () => {
  const a: ViewportKey = { url: "http://127.0.0.1:5173", width: 1024, height: 768, scrollX: 0, scrollY: 0, zoomScale: 1 };
  const b: ViewportKey = { url: "http://127.0.0.1:5173", width: 1024, height: 768, scrollX: 100, scrollY: 0, zoomScale: 1 };
  assert.equal(isNearlyEqual(a, b), false);
  const c: ViewportKey = { url: "http://127.0.0.1:5173", width: 1024, height: 768, scrollX: 0.3, scrollY: 0, zoomScale: 1 };
  assert.equal(isNearlyEqual(a, c), true);
});

test("viewport zoom tolerance", () => {
  const a: ViewportKey = { url: "http://127.0.0.1:5173", width: 1024, height: 768, scrollX: 0, scrollY: 0, zoomScale: 1.0 };
  const b: ViewportKey = { url: "http://127.0.0.1:5173", width: 1024, height: 768, scrollX: 0, scrollY: 0, zoomScale: 1.01 };
  assert.equal(isNearlyEqual(a, b), true);
  const c: ViewportKey = { url: "http://127.0.0.1:5173", width: 1024, height: 768, scrollX: 0, scrollY: 0, zoomScale: 1.05 };
  assert.equal(isNearlyEqual(a, c), false);
});

test("canonical dedupe key stability", () => {
  // Simulate Swift CanonicalStroke.dedupeKey: qx_qy_color_width_count
  function dedupeKey(cssX: number, cssY: number, color: string, width: number, count: number): string {
    const qx = Math.round(cssX * 10);
    const qy = Math.round(cssY * 10);
    return `${qx}_${qy}_${color}_${Math.round(width * 10)}_${count}`;
  }
  const k1 = dedupeKey(100.04, 200.04, "FF0000", 4, 10);
  const k2 = dedupeKey(100.06, 200.06, "FF0000", 4, 10);
  // 100.04*10=1000.4→1000, 100.06*10=1000.6→1001 => differs by 1, but should be considered same with 0.5 tolerance? Our Swift dedupe uses quantized first point, so they would be different keys and not deduped.
  // This test documents that micro jitter near bucket boundary still creates new key; isNearlyEqual at viewport level is the primary coalescing.
  assert.notEqual(k1, k2);
  const k3 = dedupeKey(100.04, 200.04, "FF0000", 4, 10);
  assert.equal(k1, k3);
});

test("12 MiB budget - server rejects over budget", () => {
  const jpeg = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(1024)]).toString("base64");
  // 8 captures each ~1 KiB decoded => total ~8 KiB under budget
  const small = Array(8).fill(jpeg);
  assert.equal(wouldExceedBudget(small), false);
  // 8 captures each 2 MiB decoded => total 16 MiB over budget
  const largeB64 = Buffer.alloc(2 * 1024 * 1024).toString("base64"); // 2 MiB decoded -> base64 ~2.7 MiB string
  const large = Array(8).fill(largeB64);
  assert.equal(wouldExceedBudget(large), true);
});

test("adaptive target per capture respects per-capture and total budget", () => {
  assert.equal(adaptiveTargetPerCapture(8), 1572864, "12MiB/8 = 1.5 MiB < 3 MiB limit");
  assert.equal(adaptiveTargetPerCapture(1), 3145728, "12MiB/1 capped to 3 MiB per-capture limit");
  assert.equal(adaptiveTargetPerCapture(4), 3145728, "12MiB/4 = 3 MiB exactly");
  assert.equal(adaptiveTargetPerCapture(2), 3145728, "12MiB/2 = 6 MiB but capped to 3 MiB");
});

test("CSS page coordinate conversion round-trip", () => {
  function viewToCSS(viewX: number, viewY: number, scrollX: number, scrollY: number, zoom: number): [number, number] {
    return [viewX / Math.max(zoom, 0.0001) + scrollX, viewY / Math.max(zoom, 0.0001) + scrollY];
  }
  function cssToView(cssX: number, cssY: number, scrollX: number, scrollY: number, zoom: number): [number, number] {
    return [(cssX - scrollX) * Math.max(zoom, 0.0001), (cssY - scrollY) * Math.max(zoom, 0.0001)];
  }
  const scrollX = 100, scrollY = 200, zoom = 1.5;
  const view = [150, 300];
  const css = viewToCSS(view[0], view[1], scrollX, scrollY, zoom);
  const back = cssToView(css[0], css[1], scrollX, scrollY, zoom);
  assert.equal(Math.round(back[0]), Math.round(view[0]));
  assert.equal(Math.round(back[1]), Math.round(view[1]));
  // Reproject to different viewport
  const otherScrollX = 120, otherZoom = 2.0;
  const otherView = cssToView(css[0], css[1], otherScrollX, 200, otherZoom);
  // CSS should be stable, view should shift by (scroll diff * zoom)
  assert.ok(otherView[0] !== view[0]);
});

test("HMR integer revision monotonic and precise sync", () => {
  // Simulate server counter and demo-web sync
  let serverCounter = 0;
  const nextServerRevision = () => String(++serverCounter);
  let sessionStorage = "0";
  const notify = (precise: string | null) => {
    if (precise != null) {
      sessionStorage = precise;
      return Number(precise);
    }
    const rev = (Number(sessionStorage) || 0) + 1;
    sessionStorage = String(rev);
    return rev;
  };
  // First HMR without precise file -> fallback increment
  assert.equal(notify(null), 1);
  // Server successful run produces "1", demo-web fetches precise
  const serverRev1 = nextServerRevision(); // "1"
  assert.equal(notify(serverRev1), 1);
  assert.equal(sessionStorage, "1");
  // Extra manual HMR without server (drift) -> fallback
  assert.equal(notify(null), 2);
  // Next server run produces "2", demo-web should sync back to "2" even though local was 2, stays in sync
  const serverRev2 = nextServerRevision(); // "2"
  assert.equal(notify(serverRev2), 2);
  // Server run 3, local still 2, should jump to 3
  const serverRev3 = nextServerRevision(); // "3"
  assert.equal(notify(serverRev3), 3);
  assert.equal(sessionStorage, "3");
});
