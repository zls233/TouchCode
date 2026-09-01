import { spawn, type ChildProcess } from "node:child_process";
import os from "node:os";

export const touchCodeBonjourServiceType = "_touchcode._tcp";

export function bonjourRegistrationArguments(input: {
  name: string;
  port: number;
}) {
  return [
    "-R",
    input.name,
    touchCodeBonjourServiceType,
    "local.",
    String(input.port),
    "v=1",
    "role=host",
  ];
}

export class BonjourRegistration {
  private process: ChildProcess | undefined;

  constructor(
    private readonly port: number,
    private readonly name = `${os.hostname().replace(/\.local\.?$/i, "")} TouchCode`,
  ) {}

  start() {
    if (this.process) return;
    const child = spawn("/usr/bin/dns-sd", bonjourRegistrationArguments({
      name: this.name,
      port: this.port,
    }), {
      stdio: ["ignore", "ignore", "pipe"],
    });
    child.stderr?.on("data", () => undefined);
    child.once("error", () => {
      if (this.process === child) this.process = undefined;
    });
    child.once("exit", () => {
      if (this.process === child) this.process = undefined;
    });
    this.process = child;
  }

  stop() {
    const child = this.process;
    this.process = undefined;
    if (child && child.exitCode === null && !child.killed) child.kill("SIGTERM");
  }
}
