// Device tokens: base64url(payload).base64url(HMAC-SHA256(TOKEN_SECRET, payload)).

import type { Env } from "../env";
import { HttpError } from "../http";
import { bytesEqual, fromBase64, fromUtf8, toBase64Url, utf8 } from "../util/bytes";

export const DEVICE_TOKEN_TTL_SECONDS = 24 * 60 * 60;

export interface DevicePrincipal {
  /** Device id: App Attest key id, or "anon:<uuid>" for anonymous devices. */
  sub: string;
  /** True when the device passed App Attest. */
  att: boolean;
  exp: number;
}

async function hmac(secret: string, data: Uint8Array): Promise<Uint8Array> {
  if (!secret || secret.length < 16) throw new Error("TOKEN_SECRET is not configured");
  const key = await crypto.subtle.importKey("raw", utf8(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return new Uint8Array(await crypto.subtle.sign("HMAC", key, data));
}

export async function issueDeviceToken(
  env: Env,
  sub: string,
  attested: boolean,
  nowSeconds = Math.floor(Date.now() / 1000),
): Promise<{ token: string; expires_at: number }> {
  const payload: DevicePrincipal = { sub, att: attested, exp: nowSeconds + DEVICE_TOKEN_TTL_SECONDS };
  const body = toBase64Url(utf8(JSON.stringify(payload)));
  const signature = toBase64Url(await hmac(env.TOKEN_SECRET, utf8(body)));
  return { token: `${body}.${signature}`, expires_at: payload.exp };
}

export async function verifyDeviceToken(env: Env, token: string, nowSeconds = Math.floor(Date.now() / 1000)) {
  const [body, signature, extra] = token.split(".");
  if (!body || !signature || extra !== undefined) return null;
  const expected = await hmac(env.TOKEN_SECRET, utf8(body));
  let provided: Uint8Array;
  try {
    provided = fromBase64(signature);
  } catch {
    return null;
  }
  if (!bytesEqual(expected, provided)) return null;
  try {
    const payload = JSON.parse(fromUtf8(fromBase64(body))) as DevicePrincipal;
    if (typeof payload.sub !== "string" || typeof payload.exp !== "number") return null;
    if (payload.exp <= nowSeconds) return null;
    return payload;
  } catch {
    return null;
  }
}

/** Resolves the calling device from the Authorization header and applies the per-device rate limit. */
export async function authenticate(request: Request, env: Env): Promise<DevicePrincipal> {
  const header = request.headers.get("authorization") ?? "";
  const match = /^Bearer\s+(.+)$/i.exec(header);
  const principal = match ? await verifyDeviceToken(env, match[1].trim()) : null;
  if (!principal) throw new HttpError(401, "unauthorized", "A valid device token is required");
  if (!principal.att && env.ATTEST_MODE === "enforce") {
    throw new HttpError(401, "attestation_required", "This device must pass App Attest");
  }
  if (env.DEVICE_LIMITER) {
    const { success } = await env.DEVICE_LIMITER.limit({ key: principal.sub });
    if (!success) throw new HttpError(429, "rate_limited", "Too many requests", { retry_after: 60 }, { "retry-after": "60" });
  }
  return principal;
}

export async function limitByIp(request: Request, env: Env): Promise<void> {
  if (!env.IP_LIMITER) return;
  const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
  const { success } = await env.IP_LIMITER.limit({ key: ip });
  if (!success) throw new HttpError(429, "rate_limited", "Too many requests", { retry_after: 60 }, { "retry-after": "60" });
}
