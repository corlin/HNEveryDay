import { authenticate } from "../auth/token";
import type { Env } from "../env";
import { HttpError, json, readJson, requireString } from "../http";
import {
  assertTransactionAcceptable,
  bindDevice,
  EntitlementError,
  saveSubscription,
  stateFromTransaction,
  stateWithAppleStatus,
  type SubscriptionState,
} from "../subscription/entitlement";
import {
  JwsError,
  verifyAppleJws,
  type NotificationPayload,
  type RenewalInfoPayload,
  type TransactionPayload,
} from "../subscription/jws";
import { getSubscriptionStatuses } from "../subscription/server-api";

/** Prefer the App Store Server API's latest status over the (possibly stale) client-supplied transaction. */
async function reconcile(env: Env, tx: TransactionPayload, base: SubscriptionState): Promise<SubscriptionState> {
  const entries = await getSubscriptionStatuses(env, tx.originalTransactionId, tx.environment !== "Production").catch(() => null);
  const entry = entries?.find((e) => e.originalTransactionId === tx.originalTransactionId);
  if (!entry) return base;
  try {
    const latest = await verifyAppleJws<TransactionPayload>(entry.signedTransactionInfo);
    const renewal = await verifyAppleJws<RenewalInfoPayload>(entry.signedRenewalInfo).catch(() => undefined);
    assertTransactionAcceptable(env, latest);
    return stateWithAppleStatus(stateFromTransaction(latest, renewal), entry.status, renewal);
  } catch (error) {
    console.warn("reconcile failed", String(error));
    return base;
  }
}

/** POST /api/v1/subscription/verify { signed_transaction } */
export async function handleVerifySubscription(request: Request, env: Env): Promise<Response> {
  const principal = await authenticate(request, env);
  const body = await readJson<Record<string, unknown>>(request, 32 * 1024);
  const signed = requireString(body.signed_transaction, "signed_transaction", 24 * 1024);

  let tx: TransactionPayload;
  try {
    tx = await verifyAppleJws<TransactionPayload>(signed);
    assertTransactionAcceptable(env, tx);
  } catch (error) {
    if (error instanceof JwsError || error instanceof EntitlementError) {
      console.warn("transaction rejected", error.message);
      throw new HttpError(400, "invalid_transaction", "The transaction could not be verified");
    }
    throw error;
  }

  const state = await reconcile(env, tx, stateFromTransaction(tx));
  await saveSubscription(env, state);
  const active = state.status === "active" && !!state.expiresAt && state.expiresAt > Date.now();
  if (active) await bindDevice(env, state.originalTransactionId, principal.sub);

  return json({
    tier: active ? "pro" : "free",
    status: state.status,
    product_id: state.productId,
    expires_at: state.expiresAt,
  });
}

function stateForNotification(payload: NotificationPayload, base: SubscriptionState, renewal?: RenewalInfoPayload): SubscriptionState {
  const status = payload.data?.status;
  if (typeof status === "number") return stateWithAppleStatus(base, status, renewal);
  switch (payload.notificationType) {
    case "REFUND":
      return { ...base, status: "refunded" };
    case "REVOKE":
      return { ...base, status: "revoked" };
    case "EXPIRED":
    case "GRACE_PERIOD_EXPIRED":
      return { ...base, status: "expired" };
    default:
      return base;
  }
}

/** POST /api/v1/appstore/notifications — App Store Server Notifications V2. */
export async function handleAppStoreNotification(request: Request, env: Env): Promise<Response> {
  const body = await readJson<{ signedPayload?: unknown }>(request, 64 * 1024);
  const signedPayload = requireString(body.signedPayload, "signedPayload", 60 * 1024);

  let payload: NotificationPayload;
  try {
    payload = await verifyAppleJws<NotificationPayload>(signedPayload);
  } catch (error) {
    console.warn("notification rejected", String(error));
    throw new HttpError(400, "invalid_notification", "Notification could not be verified");
  }
  if (payload.data?.bundleId && payload.data.bundleId !== env.APP_BUNDLE_ID) {
    return json({ ok: true, ignored: "bundle" });
  }

  let tx: TransactionPayload | null = null;
  let renewal: RenewalInfoPayload | undefined;
  if (payload.data?.signedTransactionInfo) {
    tx = await verifyAppleJws<TransactionPayload>(payload.data.signedTransactionInfo).catch(() => null);
    if (payload.data.signedRenewalInfo) {
      renewal = await verifyAppleJws<RenewalInfoPayload>(payload.data.signedRenewalInfo).catch(() => undefined);
    }
  }

  const inserted = await env.DB.prepare(
    `INSERT OR IGNORE INTO notification_log (notification_uuid, notification_type, subtype, original_transaction_id, received_at)
     VALUES (?, ?, ?, ?, ?)`,
  )
    .bind(payload.notificationUUID, payload.notificationType, payload.subtype ?? null, tx?.originalTransactionId ?? null, Date.now())
    .run();
  if (!inserted.meta.changes) return json({ ok: true, duplicate: true });

  if (tx) {
    try {
      assertTransactionAcceptable(env, tx);
      await saveSubscription(env, stateForNotification(payload, stateFromTransaction(tx, renewal), renewal));
    } catch (error) {
      if (!(error instanceof EntitlementError)) throw error;
      console.warn("notification transaction ignored", error.message);
    }
  }
  return json({ ok: true });
}
