import { createBridgeApp } from "./app.js";
import { localIPv4Address } from "./demo-session-manager.js";

const host = process.env.TOUCHCODE_HOST ?? "0.0.0.0";
const port = Number(process.env.TOUCHCODE_PORT ?? 4317);
const bridgeBaseURL = `http://${localIPv4Address()}:${port}`;
const app = await createBridgeApp({ bridgeBaseURL });

await app.listen({ host, port });
app.log.info({ host, port }, "TouchCode Mac bridge runtime started");
