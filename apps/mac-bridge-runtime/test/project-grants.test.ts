import assert from "node:assert/strict";
import test from "node:test";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { ProjectGrantStore } from "../src/project-grants.js";

test("rejects paths outside a granted project", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "touchcode-grant-"));
  const store = new ProjectGrantStore();
  const grant = await store.grant(root);
  await assert.rejects(() => store.resolve(grant.id, "../secret.txt"), /escapes project root/);
});

test("resolves project-relative paths", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "touchcode-grant-"));
  const store = new ProjectGrantStore();
  const grant = await store.grant(root);
  assert.equal(
    await store.resolve(grant.id, "src/App.tsx"),
    path.join(grant.canonicalRoot, "src/App.tsx"),
  );
});

