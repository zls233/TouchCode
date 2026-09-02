import { createBridgeApp } from "./app.js";
import { localIPv4Address } from "./demo-session-manager.js";
import {
  consumeHostIdentityFromEnvironment,
  consumeIdentityHelperPathFromEnvironment,
} from "./host-identity.js";
import { HelperHostIdentitySigner } from "./host-identity-signer.js";

const host = process.env.TOUCHCODE_HOST ?? "0.0.0.0";
const port = Number(process.env.TOUCHCODE_PORT ?? 4317);
const bridgeBaseURL = `http://${localIPv4Address()}:${port}`;
const hostIdentity = consumeHostIdentityFromEnvironment();
const helperPath = consumeIdentityHelperPathFromEnvironment();
if (helperPath && !hostIdentity) {
  throw new Error("TouchCode identity helper requires a validated host identity");
}
const hostIdentitySigner = hostIdentity && helperPath
  ? new HelperHostIdentitySigner(helperPath, hostIdentity)
  : undefined;
const app = await createBridgeApp({
  bridgeBaseURL,
  ...(hostIdentity ? { hostIdentity } : {}),
  ...(hostIdentitySigner ? { hostIdentitySigner } : {}),
});

await app.listen({ host, port });
app.log.info({ host, port }, "TouchCode Mac bridge runtime started");
