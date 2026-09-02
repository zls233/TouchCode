import { createBridgeApp } from "./app.js";
import { localIPv4Address } from "./demo-session-manager.js";
import { consumeHostIdentityFromEnvironment } from "./host-identity.js";

const host = process.env.TOUCHCODE_HOST ?? "0.0.0.0";
const port = Number(process.env.TOUCHCODE_PORT ?? 4317);
const bridgeBaseURL = `http://${localIPv4Address()}:${port}`;
const hostIdentity = consumeHostIdentityFromEnvironment();
const app = await createBridgeApp({
  bridgeBaseURL,
  ...(hostIdentity ? { hostIdentity } : {}),
});

await app.listen({ host, port });
app.log.info({ host, port }, "TouchCode Mac bridge runtime started");
