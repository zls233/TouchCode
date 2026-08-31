import path from "node:path";
import { parseArgs } from "node:util";

export type CliOptions = {
  projectPath: string;
  projectCwd: string;
  bridgePort: number;
  previewPort: number;
  previewCommand: string[];
};

export const cliUsage = `Usage:
  touchcode --preview-port 5173 -- pnpm dev -- --host 0.0.0.0 --port 5173
  touchcode --project /absolute/repo --cwd apps/web --preview-port 5173 -- pnpm dev

Options:
  --project       Clean Git repository to edit (defaults to current directory)
  --cwd           Preview command directory inside the repository (defaults to .)
  --bridge-port   TouchCode bridge port (defaults to 4317)
  --preview-port  Port on which the preview command will listen (required)
  --help, -h      Show this help
  --version, -v   Show version`;

export const cliVersion = "0.1.0";

function port(value: string | undefined, name: string, fallback?: number) {
  if (value === undefined && fallback !== undefined) return fallback;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > 65_535) {
    throw new Error(`${name} must be an integer between 1 and 65535`);
  }
  return parsed;
}

export function parseCliOptions(argv: string[]): CliOptions | { help: true } | { version: true } {
  const separator = argv.indexOf("--");
  const optionArguments = separator === -1 ? argv : argv.slice(0, separator);
  const previewCommand = separator === -1 ? [] : argv.slice(separator + 1);
  const parsed = parseArgs({
    args: optionArguments,
    allowPositionals: false,
    strict: true,
    options: {
      project: { type: "string" },
      cwd: { type: "string" },
      "bridge-port": { type: "string" },
      "preview-port": { type: "string" },
      help: { type: "boolean", short: "h" },
      version: { type: "boolean", short: "v" },
    },
  });

  if (parsed.values.help) return { help: true };
  if (parsed.values.version) return { version: true };
  if (previewCommand.length === 0) {
    throw new Error("A preview command is required after -- (e.g. -- pnpm dev)");
  }

  return {
    projectPath: path.resolve(parsed.values.project ?? process.cwd()),
    projectCwd: parsed.values.cwd ?? ".",
    bridgePort: port(parsed.values["bridge-port"], "--bridge-port", 4317),
    previewPort: port(parsed.values["preview-port"], "--preview-port"),
    previewCommand,
  };
}
