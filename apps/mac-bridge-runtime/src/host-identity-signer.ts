import { spawn } from "node:child_process";
import path from "node:path";
import {
  ecdsaP256DERSignatureSchema,
  encodeBase64URL,
  verifyP256DERSignature,
  type DeviceIdentity,
} from "@touchcode/protocol";

const maximumTranscriptBytes = 64 * 1_024;
const maximumHelperOutputBytes = 4_096;
const helperTimeoutMilliseconds = 5_000;

export type IdentityHelperRunner = (
  helperPath: string,
  encodedTranscript: string,
) => Promise<string>;

export interface HostIdentitySigner {
  sign(transcript: Uint8Array): Promise<string>;
}

export class HelperHostIdentitySigner implements HostIdentitySigner {
  private readonly helperPath: string;
  private readonly identity: DeviceIdentity;
  private readonly runner: IdentityHelperRunner;

  constructor(helperPath: string, identity: DeviceIdentity, runner: IdentityHelperRunner = runIdentityHelper) {
    if (!path.isAbsolute(helperPath) || helperPath.includes("\0") || helperPath.length > 1_024) {
      throw new Error("TouchCode identity helper path must be a bounded absolute path");
    }
    this.helperPath = helperPath;
    this.identity = identity;
    this.runner = runner;
  }

  async sign(transcript: Uint8Array): Promise<string> {
    if (transcript.byteLength < 1 || transcript.byteLength > maximumTranscriptBytes) {
      throw new Error("TouchCode identity transcript size is invalid");
    }
    const output = await this.runner(this.helperPath, encodeBase64URL(transcript));
    const signature = ecdsaP256DERSignatureSchema.parse(output);
    if (!verifyP256DERSignature(this.identity.publicKeyX963, transcript, signature)) {
      throw new Error("TouchCode identity helper signature does not match the advertised identity");
    }
    return signature;
  }
}

export function runIdentityHelper(helperPath: string, encodedTranscript: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn(helperPath, ["sign"], {
      env: {},
      shell: false,
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = Buffer.alloc(0);
    let stderr = Buffer.alloc(0);
    let settled = false;

    const finish = (error?: Error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      if (error) reject(error);
      else resolve(stdout.toString("utf8"));
    };
    const append = (current: Buffer, chunk: Buffer, label: string) => {
      const combined = Buffer.concat([current, chunk]);
      if (combined.length > maximumHelperOutputBytes) {
        child.kill("SIGKILL");
        finish(new Error(`TouchCode identity helper ${label} exceeded the output limit`));
      }
      return combined;
    };
    const timeout = setTimeout(() => {
      child.kill("SIGKILL");
      finish(new Error("TouchCode identity helper timed out"));
    }, helperTimeoutMilliseconds);

    child.stdout.on("data", (chunk: Buffer) => { stdout = append(stdout, chunk, "stdout"); });
    child.stderr.on("data", (chunk: Buffer) => { stderr = append(stderr, chunk, "stderr"); });
    child.once("error", (error) => finish(error));
    child.once("close", (code, signal) => {
      if (code !== 0) {
        finish(new Error(`TouchCode identity helper failed (${signal ?? `status ${code ?? "unknown"}`})`));
        return;
      }
      finish();
    });
    child.stdin.once("error", (error) => finish(error));
    child.stdin.end(encodedTranscript);
  });
}
