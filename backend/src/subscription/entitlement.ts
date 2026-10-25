import type { Env } from "../env";
import { flag, intVar, listVar } from "../env";
import type { RenewalInfoPayload, TransactionPayload } from "./jws";

export type SubscriptionStatus = "active" | "expired" | "revoked" | "refunded" | "billing_retry";

export interface SubscriptionState {
  originalTransactionId: string;
  productId: string;
  status: SubscriptionStatus;
  expiresAt: number | null;
  environment: string;
  appAccountToken: string | null;
  autoRenew: boolean | null;
}

export class EntitlementError extends Error {}

/** Checks that a decoded transaction belongs to this app and is a Pro product in an allowed environment. */
export function assertTransactionAcceptable(env: Env, tx: TransactionPayload): void {
  if (tx.bundleId !== env.APP_BUNDLE_ID) throw new EntitlementError("bundle id mismatch");
  if (!listVar(env.PRO_PRODUCT_IDS).includes(tx.productId)) throw new EntitlementError("not a Pro product");
  if (tx.environment !== "Production" && !flag(env.ALLOW_SANDBOX)) throw new EntitlementError("sandbox transactions are not accepted");
}

/** Status from the transaction alone (used when no fresher source is available). */
export function stateFromTransaction(tx: TransactionPayload, renewal?: RenewalInfoPayload, now = Date.now()): SubscriptionState {
  let status: SubscriptionStatus;
  let expiresAt = tx.expiresDate ?? null;
  if (tx.revocationDate) status = tx.revocationReason === undefined ? "revoked" : "refunded";
  else if (expiresAt && expiresAt > now) status = "active";
  else if (renewal?.gracePeriodExpiresDate && renewal.gracePeriodExpiresDate > now) {
    status = "active";
    expiresAt = renewal.gracePeriodExpiresDate;
  } else if (renewal?.isInBillingRetryPeriod) status = "billing_retry";
  else status = "expired";

  return {
    originalTransactionId: tx.originalTransactionId,
    productId: tx.productId,
    status,
    expiresAt,
    environment: tx.environment ?? "Production",
    appAccountToken: tx.appAccountToken ?? null,
    autoRenew: renewal?.autoRenewStatus === undefined ? null : renewal.autoRenewStatus === 1,
  };
}

/** Maps App Store status codes (subscription status API / notification data.status). */
export function stateWithAppleStatus(base: SubscriptionState, appleStatus: number, renewal?: RenewalInfoPayload): SubscriptionState {
  switch (appleStatus) {
    case 1:
      return { ...base, status: "active" };
    case 2:
      return { ...base, status: "expired" };
    case 3:
      return { ...base, status: "billing_retry" };
    case 4:
      return { ...base, status: "active", expiresAt: renewal?.gracePeriodExpiresDate ?? base.expiresAt };
    case 5:
      return { ...base, status: "revoked" };
    default:
      return base;
  }
}

export async function saveSubscription(env: Env, state: SubscriptionState, now = Date.now()): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO subscriptions (original_transaction_id, product_id, status, expires_at, environment, app_account_token, auto_renew, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(original_transaction_id) DO UPDATE SET product_id = excluded.product_id, status = excluded.status,
       expires_at = excluded.expires_at, environment = excluded.environment,
       app_account_token = COALESCE(excluded.app_account_token, subscriptions.app_account_token),
       auto_renew = COALESCE(excluded.auto_renew, subscriptions.auto_renew), updated_at = excluded.updated_at`,
  )
    .bind(
      state.originalTransactionId,
      state.productId,
      state.status,
      state.expiresAt,
      state.environment,
      state.appAccountToken,
      state.autoRenew === null ? null : state.autoRenew ? 1 : 0,
      now,
    )
    .run();
}

/** Binds a device to a subscription, evicting the least recently seen devices beyond the limit. */
export async function bindDevice(env: Env, originalTransactionId: string, deviceId: string, now = Date.now()): Promise<void> {
  const max = intVar(env.MAX_DEVICES_PER_SUBSCRIPTION, 5);
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO subscription_devices (original_transaction_id, device_id, last_seen) VALUES (?, ?, ?)
       ON CONFLICT(original_transaction_id, device_id) DO UPDATE SET last_seen = excluded.last_seen`,
    ).bind(originalTransactionId, deviceId, now),
    env.DB.prepare(
      `DELETE FROM subscription_devices WHERE original_transaction_id = ?1 AND device_id NOT IN (
         SELECT device_id FROM subscription_devices WHERE original_transaction_id = ?1 ORDER BY last_seen DESC LIMIT ?2)`,
    ).bind(originalTransactionId, max),
  ]);
}
