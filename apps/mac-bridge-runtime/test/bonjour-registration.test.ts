import assert from "node:assert/strict";
import test from "node:test";
import {
  bonjourRegistrationArguments,
  touchCodeBonjourServiceType,
} from "../src/bonjour-registration.js";

test("registers the bridge with a minimal non-secret Bonjour record", () => {
  assert.equal(touchCodeBonjourServiceType, "_touchcode._tcp");
  assert.deepEqual(
    bonjourRegistrationArguments({ name: "Test Mac TouchCode", port: 4317 }),
    [
      "-R",
      "Test Mac TouchCode",
      "_touchcode._tcp",
      "local.",
      "4317",
      "v=1",
      "role=host",
    ],
  );
});
