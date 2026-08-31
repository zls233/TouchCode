import assert from "node:assert/strict";
import test from "node:test";
import { parseCliOptions } from "../src/cli-options.js";

test("parses bridge options and preserves the preview command after --", () => {
  const options = parseCliOptions([
    "--project", "/tmp/example",
    "--cwd", "apps/web",
    "--bridge-port", "4318",
    "--preview-port", "5174",
    "--", "pnpm", "dev", "--", "--host", "0.0.0.0",
  ]);

  assert.deepEqual(options, {
    projectPath: "/tmp/example",
    projectCwd: "apps/web",
    bridgePort: 4318,
    previewPort: 5174,
    previewCommand: ["pnpm", "dev", "--", "--host", "0.0.0.0"],
  });
});

test("uses the documented defaults when optional options are omitted", () => {
  const options = parseCliOptions(["--preview-port", "5173", "--", "pnpm", "dev"]);
  assert.equal("help" in options, false);
  if ("help" in options) return;
  assert.equal(options.projectCwd, ".");
  assert.equal(options.bridgePort, 4317);
  assert.deepEqual(options.previewCommand, ["pnpm", "dev"]);
});

test("requires a preview command and a valid preview port", () => {
  assert.throws(
    () => parseCliOptions(["--preview-port", "5173"]),
    /A preview command is required after --/,
  );
  assert.throws(
    () => parseCliOptions(["--preview-port", "0", "--", "pnpm", "dev"]),
    /--preview-port must be an integer between 1 and 65535/,
  );
});

test("supports help without requiring a preview command", () => {
  assert.deepEqual(parseCliOptions(["--help"]), { help: true });
  assert.deepEqual(parseCliOptions(["-h"]), { help: true });
});

test("supports version without requiring a preview command", () => {
  assert.deepEqual(parseCliOptions(["--version"]), { version: true });
  assert.deepEqual(parseCliOptions(["-v"]), { version: true });
});

test("rejects unknown options before the command separator", () => {
  assert.throws(
    () => parseCliOptions(["--preview-port", "5173", "--unknown", "--", "pnpm", "dev"]),
    /Unknown option/,
  );
});
