import assert from "node:assert/strict";
import test from "node:test";

// Simulate Swift compressedCaptures ladder: qualities [0.74,0.6,0.5,0.35,0.22,0.12], dims [1600,1200,900,700,500]
// For Node test, simulate size reduction as: newSize = originalSize * (dim/1600)^2 * quality / 0.74
function simulateRecompress(originalSize: number, dim: number, quality: number): number {
  const scale = dim / 1600;
  return Math.floor(originalSize * scale * scale * (quality / 0.74));
}

function adaptiveTargetPerCapture(count: number, budget = 12 * 1024 * 1024, perCaptureLimit = 3 * 1024 * 1024): number {
  return Math.min(perCaptureLimit, Math.floor(budget / Math.max(count, 1)));
}

function compressedSize(originalSize: number, targetPerCapture: number): number {
  const qualities = [0.74, 0.6, 0.5, 0.35, 0.22, 0.12];
  const dims = [1600, 1200, 900, 700, 500];
  for (const dim of dims) {
    for (const q of qualities) {
      const candidate = simulateRecompress(originalSize, dim, q);
      if (candidate <= targetPerCapture) return candidate;
    }
  }
  // smallest attempt
  return simulateRecompress(originalSize, 500, 0.12);
}

test("adaptive compression: 8 large JPEGs each 4 MiB should fit within 12 MiB after ladder", () => {
  const originalPerCapture = 4 * 1024 * 1024; // 4 MiB each, 32 MiB total over budget
  const count = 8;
  const target = adaptiveTargetPerCapture(count); // 12/8=1.5 MiB
  const compressed = Array(count).fill(originalPerCapture).map((s) => compressedSize(s, target));
  const total = compressed.reduce((a, b) => a + b, 0);
  assert.ok(total <= 12 * 1024 * 1024, `total ${total} should be <= 12 MiB`);
  assert.ok(compressed.every((s) => s <= 3 * 1024 * 1024), "each should be <= 3 MiB per-capture limit");
  assert.equal(target, 1572864);
});

test("adaptive compression: single 10 MiB JPEG should be capped to 3 MiB", () => {
  const original = 10 * 1024 * 1024;
  const target = adaptiveTargetPerCapture(1); // 3 MiB
  const compressed = compressedSize(original, target);
  assert.ok(compressed <= 3 * 1024 * 1024);
  assert.ok(compressed < original);
});

test("adaptive compression: small captures under budget are not recompressed", () => {
  const small = 500 * 1024; // 500 KiB
  const target = adaptiveTargetPerCapture(8);
  // Simulate Swift guard: if data.count <= targetPerCapture, return original
  const shouldRecompress = small > target;
  assert.equal(shouldRecompress, false);
});

test("budget calculation respects per-capture limit for few captures", () => {
  // 2 captures: budget 12/2=6 MiB but per-capture limit 3 MiB, so target is 3 MiB
  assert.equal(adaptiveTargetPerCapture(2), 3145728);
  // 4 captures: 12/4=3 MiB exactly
  assert.equal(adaptiveTargetPerCapture(4), 3145728);
  // 8 captures: 1.5 MiB
  assert.equal(adaptiveTargetPerCapture(8), 1572864);
});

test("real JPEG header validation: valid JPEG must start with FF D8 FF", () => {
  const valid = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]);
  const invalid = Buffer.from([0x00, 0x00, 0x00, 0x00]);
  const isValidJpeg = (b: Buffer) => b.length >= 4 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff;
  assert.equal(isValidJpeg(valid), true);
  assert.equal(isValidJpeg(invalid), false);
  // Simulate bridge decodeJPEG check
  const base64Valid = valid.toString("base64");
  const decoded = Buffer.from(base64Valid, "base64");
  assert.equal(isValidJpeg(decoded), true);
});

test("viewport quantization: 0.1 and 0.01 thresholds", () => {
  const quantize = (v: number, factor: number) => Math.round(v * factor) / factor;
  // width*10
  assert.equal(quantize(1024.04, 10), 1024.0);
  assert.equal(quantize(1024.06, 10), 1024.1);
  // scale*100
  assert.equal(quantize(1.004, 100), 1.0);
  assert.equal(quantize(1.006, 100), 1.01);
  // pageLeft*10
  assert.equal(quantize(100.04, 10), 100.0);
  assert.equal(quantize(100.06, 10), 100.1);
});
