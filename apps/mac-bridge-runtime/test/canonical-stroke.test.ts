import assert from "node:assert/strict";
import test from "node:test";

// Mirror Swift CanonicalStroke dedupe and reprojection logic
type Viewport = { scrollX: number; scrollY: number; zoomScale: number };

function viewToCSS(viewX: number, viewY: number, vp: Viewport): [number, number] {
  return [viewX / Math.max(vp.zoomScale, 0.0001) + vp.scrollX, viewY / Math.max(vp.zoomScale, 0.0001) + vp.scrollY];
}
function cssToView(cssX: number, cssY: number, vp: Viewport): [number, number] {
  return [(cssX - vp.scrollX) * Math.max(vp.zoomScale, 0.0001), (cssY - vp.scrollY) * Math.max(vp.zoomScale, 0.0001)];
}

function dedupeKey(cssX: number, cssY: number, color: string, width: number, count: number): string {
  const qx = Math.round(cssX * 10);
  const qy = Math.round(cssY * 10);
  return `${qx}_${qy}_${color}_${Math.round(width * 10)}_${count}`;
}

test("canonical dedupe: same physical stroke in different viewports yields same CSS and same dedupeKey", () => {
  const vpA: Viewport = { scrollX: 0, scrollY: 0, zoomScale: 1 };
  const vpB: Viewport = { scrollX: 100, scrollY: 50, zoomScale: 2 };
  // A point at view (150,200) in vpA corresponds to CSS (150,200)
  const viewA: [number, number] = [150, 200];
  const cssA = viewToCSS(viewA[0], viewA[1], vpA);
  // Same physical point should appear at view (100,300) in vpB: (css - scroll)*zoom
  const viewB = cssToView(cssA[0], cssA[1], vpB);
  const cssB = viewToCSS(viewB[0], viewB[1], vpB);
  assert.equal(Math.round(cssA[0] * 10), Math.round(cssB[0] * 10));
  assert.equal(Math.round(cssA[1] * 10), Math.round(cssB[1] * 10));
  const kA = dedupeKey(cssA[0], cssA[1], "FF0000", 4, 5);
  const kB = dedupeKey(cssB[0], cssB[1], "FF0000", 4, 5);
  assert.equal(kA, kB, "same CSS should dedupe across viewports");
});

test("canonical reprojection error <1pt after round-trip", () => {
  const viewports: Viewport[] = [
    { scrollX: 0, scrollY: 0, zoomScale: 1 },
    { scrollX: 123.4, scrollY: 567.8, zoomScale: 1.5 },
    { scrollX: 0, scrollY: 0, zoomScale: 0.5 },
    { scrollX: 1000, scrollY: 2000, zoomScale: 2 },
  ];
  const originalView: [number, number] = [250.7, 400.3];
  for (const vp of viewports) {
    const css = viewToCSS(originalView[0], originalView[1], vp);
    const back = cssToView(css[0], css[1], vp);
    const errX = Math.abs(back[0] - originalView[0]);
    const errY = Math.abs(back[1] - originalView[1]);
    assert.ok(errX < 1, `errX ${errX} <1 for vp ${JSON.stringify(vp)}`);
    assert.ok(errY < 1, `errY ${errY} <1`);
  }
});

test("canonical dedupe: different color or width yields different key", () => {
  const k1 = dedupeKey(100, 100, "FF0000", 4, 10);
  const k2 = dedupeKey(100, 100, "00FF00", 4, 10);
  const k3 = dedupeKey(100, 100, "FF0000", 8, 10);
  assert.notEqual(k1, k2);
  assert.notEqual(k1, k3);
});

test("canonical dedupe: same CSS quantized to 0.1 should be stable", () => {
  // 100.04 and 100.06 quantize to 1000 and 1001 with *10, but isNearlyEqual at viewport level is primary
  // Dedupe uses quantized first point, so they would be different; this documents the bucket boundary
  const k1 = dedupeKey(100.04, 100.04, "FF0000", 4, 10);
  const k2 = dedupeKey(100.06, 100.06, "FF0000", 4, 10);
  assert.notEqual(k1, k2);
  // But within same bucket they are equal
  const k3 = dedupeKey(100.04, 100.04, "FF0000", 4, 10);
  assert.equal(k1, k3);
});

test("viewport isNearlyEqual is primary coalescing, dedupe is secondary", () => {
  const vpA = { url: "http://a", width: 1024, height: 768, scrollX: 0.3, scrollY: 0, zoomScale: 1 };
  const vpB = { url: "http://a", width: 1024, height: 768, scrollX: 0.4, scrollY: 0, zoomScale: 1 };
  const isNear = (a: typeof vpA, b: typeof vpA) => Math.abs(a.scrollX - b.scrollX) < 0.5;
  assert.equal(isNear(vpA, vpB), true, "0.1 diff should be coalesced by viewport nearlyEqual");
  // Even if dedupeKey differs by 1, viewport coalescing will keep them in same capture slot
});
