import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import test from "node:test";
import {
  deriveDeviceId,
  encodeBase64URL,
  verifyP256DERSignature,
  type DeviceIdentity,
} from "@touchcode/protocol";
import {
  HelperHostIdentitySigner,
  runIdentityHelper,
} from "../src/host-identity-signer.js";

function keyFixture() {
  const pair = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const jwk = pair.publicKey.export({ format: "jwk" });
  const publicKeyX963 = Buffer.concat([
    Buffer.from([4]),
    Buffer.from(jwk.x!, "base64url"),
    Buffer.from(jwk.y!, "base64url"),
  ]).toString("base64url");
  const identity: DeviceIdentity = {
    version: 1,
    deviceId: deriveDeviceId(publicKeyX963),
    keyAlgorithm: "p256",
    signatureAlgorithm: "ecdsa-sha256",
    signatureEncoding: "asn1-der",
    publicKeyX963,
    displayName: "TouchCode Mac",
  };
  return { pair, identity };
}

test("helper signer accepts only a signature from the advertised identity", async () => {
  const fixture = keyFixture();
  const runner = async (_path: string, encodedTranscript: string) =>
    sign("sha256", Buffer.from(encodedTranscript, "base64url"), fixture.pair.privateKey).toString("base64url");
  const signer = new HelperHostIdentitySigner("/absolute/test-helper", fixture.identity, runner);
  const transcript = Buffer.from("canonical host challenge");
  const signature = await signer.sign(transcript);
  assert.equal(verifyP256DERSignature(fixture.identity.publicKeyX963, transcript, signature), true);

  const other = keyFixture();
  const mismatched = new HelperHostIdentitySigner(
    "/absolute/test-helper",
    fixture.identity,
    async (_path, encoded) => sign("sha256", Buffer.from(encoded, "base64url"), other.pair.privateKey).toString("base64url"),
  );
  await assert.rejects(mismatched.sign(transcript), /does not match the advertised identity/);
});

test("helper signer rejects unsafe paths, invalid sizes, and failed helpers", async () => {
  const fixture = keyFixture();
  assert.throws(
    () => new HelperHostIdentitySigner("relative-helper", fixture.identity, async () => "unused"),
    /bounded absolute path/,
  );
  const signer = new HelperHostIdentitySigner("/absolute/test-helper", fixture.identity, async () => "invalid");
  await assert.rejects(signer.sign(Buffer.alloc(0)), /transcript size is invalid/);
  await assert.rejects(signer.sign(Buffer.alloc(64 * 1_024 + 1)), /transcript size is invalid/);
  await assert.rejects(signer.sign(Buffer.from("valid size")));
  await assert.rejects(runIdentityHelper("/usr/bin/false", encodeBase64URL(Buffer.from("x"))));
});
