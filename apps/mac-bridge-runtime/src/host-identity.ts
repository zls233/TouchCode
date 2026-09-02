import {
  deviceIdentitySchema,
  type DeviceIdentity,
} from "@touchcode/protocol";

export const hostIdentityEnvironmentKey = "TOUCHCODE_HOST_IDENTITY_JSON";
export const identityHelperPathEnvironmentKey = "TOUCHCODE_IDENTITY_HELPER_PATH";
export const maximumHostIdentityEnvironmentBytes = 4_096;

export function hostIdentityFromEnvironment(
  environment: NodeJS.ProcessEnv = process.env,
): DeviceIdentity | undefined {
  const value = environment[hostIdentityEnvironmentKey];
  if (value === undefined) return undefined;
  if (Buffer.byteLength(value, "utf8") > maximumHostIdentityEnvironmentBytes) {
    throw new Error("TouchCode host identity environment value is too large");
  }

  let decoded: unknown;
  try {
    decoded = JSON.parse(value);
  } catch {
    throw new Error("TouchCode host identity environment value is not valid JSON");
  }

  const parsed = deviceIdentitySchema.safeParse(decoded);
  if (!parsed.success) {
    throw new Error("TouchCode host identity environment value does not match device identity v1");
  }
  return parsed.data;
}

export function consumeHostIdentityFromEnvironment(
  environment: NodeJS.ProcessEnv = process.env,
): DeviceIdentity | undefined {
  try {
    return hostIdentityFromEnvironment(environment);
  } finally {
    delete environment[hostIdentityEnvironmentKey];
  }
}

export function consumeIdentityHelperPathFromEnvironment(
  environment: NodeJS.ProcessEnv = process.env,
): string | undefined {
  const value = environment[identityHelperPathEnvironmentKey];
  delete environment[identityHelperPathEnvironmentKey];
  return value;
}
