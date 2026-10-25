import { SELF } from "cloudflare:test";

export const BASE = "https://api.test";

export async function call(path: string, options: { method?: string; token?: string; body?: unknown; headers?: Record<string, string> } = {}) {
  const headers: Record<string, string> = { ...options.headers };
  if (options.token) headers.authorization = `Bearer ${options.token}`;
  if (options.body !== undefined) headers["content-type"] = "application/json";
  return SELF.fetch(`${BASE}${path}`, {
    method: options.method ?? (options.body === undefined ? "GET" : "POST"),
    headers,
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });
}

let ipCounter = 0;

/** Each anonymous device gets its own IP so the shared anonymous IP pool does not interfere between tests. */
export async function anonymousDevice(): Promise<{ token: string; deviceId: string; ip: string }> {
  const ip = `10.0.0.${++ipCounter}`;
  const response = await call("/api/v1/auth/anonymous", { body: {}, headers: { "cf-connecting-ip": ip } });
  const data = (await response.json()) as { token: string; device_id: string };
  return { token: data.token, deviceId: data.device_id, ip };
}
