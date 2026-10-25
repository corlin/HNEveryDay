// App Store Server API: used to reconcile a subscription's latest status when credentials are configured.

import type { Env } from "../env";
import { pemToDer, toBase64Url, utf8 } from "../util/bytes";

export function hasServerApiCredentials(env: Env): boolean {
  return !!(env.ASC_KEY_ID && env.ASC_ISSUER_ID && env.ASC_PRIVATE_KEY);
}

async function bearerToken(env: Env): Promise<string> {
  const header = { alg: "ES256", kid: env.ASC_KEY_ID, typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  const payload = { iss: env.ASC_ISSUER_ID, iat: now, exp: now + 300, aud: "appstoreconnect-v1", bid: env.APP_BUNDLE_ID };
  const signingInput = `${toBase64Url(utf8(JSON.stringify(header)))}.${toBase64Url(utf8(JSON.stringify(payload)))}`;
  const key = await crypto.subtle.importKey("pkcs8", pemToDer(env.ASC_PRIVATE_KEY!), { name: "ECDSA", namedCurve: "P-256" }, false, [
    "sign",
  ]);
  const signature = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, utf8(signingInput)));
  return `${signingInput}.${toBase64Url(signature)}`;
}

export interface SubscriptionStatusEntry {
  originalTransactionId: string;
  /** 1 active, 2 expired, 3 billing retry, 4 grace period, 5 revoked. */
  status: number;
  signedTransactionInfo: string;
  signedRenewalInfo: string;
}

/** GET /inApps/v1/subscriptions/{transactionId}. Returns null when unavailable. */
export async function getSubscriptionStatuses(
  env: Env,
  transactionId: string,
  sandbox: boolean,
): Promise<SubscriptionStatusEntry[] | null> {
  if (!hasServerApiCredentials(env)) return null;
  const host = sandbox ? "https://api.storekit-sandbox.itunes.apple.com" : "https://api.storekit.itunes.apple.com";
  const response = await fetch(`${host}/inApps/v1/subscriptions/${encodeURIComponent(transactionId)}`, {
    headers: { authorization: `Bearer ${await bearerToken(env)}` },
  });
  if (!response.ok) {
    console.warn("App Store Server API failed", response.status);
    return null;
  }
  const body = (await response.json()) as { data?: { lastTransactions?: SubscriptionStatusEntry[] }[] };
  return (body.data ?? []).flatMap((group) => group.lastTransactions ?? []);
}
