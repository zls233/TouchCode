export function isAllowedTunnelTarget(requestURL: string, allowedPort: number): boolean {
  try {
    const url = new URL(requestURL);
    const host = url.hostname.toLowerCase();
    const port = url.port ? Number(url.port) : url.protocol === "https:" ? 443 : 80;
    // Only allow localhost Vite port, not arbitrary LAN or external hosts.
    // Node returns IPv6 hostname with brackets as "[::1]" in some contexts.
    const isLoopback = host === "127.0.0.1" || host === "localhost" || host === "::1" || host === "[::1]";
    return isLoopback && port === allowedPort;
  } catch {
    return false;
  }
}

export function tunnelTargetFromPreviewURL(previewURL: string): string | null {
  try {
    const url = new URL(previewURL);
    if (url.protocol !== "http:" && url.protocol !== "https:") return null;
    // Preview must be on Vite's localhost port; we validate later via isAllowedTunnelTarget.
    return previewURL;
  } catch {
    return null;
  }
}
