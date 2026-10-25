import type { DevicePrincipal } from "./auth/token";
import type { QuotaKind, RemoteConfig, Tier, TierQuotas } from "./config";
import type { Env } from "./env";
import { intVar } from "./env";
import { HttpError } from "./http";

/** Anonymous devices also share a per-IP pool, so minting new anonymous ids does not reset quota. */
const ANONYMOUS_IP_POOL_FACTOR = 3;

export function utcDay(now = Date.now()): string {
  return new Date(now).toISOString().slice(0, 10);
}

export function nextUtcMidnight(now = Date.now()): number {
  const d = new Date(now);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + 1);
}

export async function resolveTier(env: Env, deviceId: string, now = Date.now()): Promise<Tier> {
  const row = await env.DB.prepare(
    `SELECT 1 AS ok FROM subscription_devices d
     JOIN subscriptions s ON s.original_transaction_id = d.original_transaction_id
     WHERE d.device_id = ? AND s.status = 'active' AND s.expires_at > ?
     LIMIT 1`,
  )
    .bind(deviceId, now)
    .first<{ ok: number }>();
  return row ? "pro" : "free";
}

export function quotaLimit(config: RemoteConfig, tier: Tier, kind: QuotaKind, attested: boolean): number {
  const base = config.quotas[tier][kind as keyof TierQuotas];
  return attested ? base : Math.max(1, Math.floor(base * config.anonymous_quota_factor));
}

export interface QuotaGrant {
  kind: QuotaKind;
  used: number;
  limit: number;
  remaining: number;
  /** Subjects that were charged, for refunds. */
  subjects: string[];
}

async function increment(env: Env, subject: string, day: string, kind: QuotaKind, limit: number, now: number) {
  return env.DB.prepare(
    `INSERT INTO usage_daily (device_id, day, kind, count, last_at) VALUES (?, ?, ?, 1, ?)
     ON CONFLICT(device_id, day, kind) DO UPDATE SET count = count + 1, last_at = excluded.last_at
     WHERE usage_daily.count < ?
     RETURNING count`,
  )
    .bind(subject, day, kind, now, limit)
    .first<{ count: number }>();
}

/**
 * Charges one unit of `kind` to the device (and, for anonymous devices, to the caller's IP pool).
 * Throws 429 quota_exceeded / slow_down.
 */
export async function consumeQuota(
  env: Env,
  request: Request,
  principal: DevicePrincipal,
  tier: Tier,
  kind: QuotaKind,
  config: RemoteConfig,
  now = Date.now(),
): Promise<QuotaGrant> {
  const day = utcDay(now);
  const limit = quotaLimit(config, tier, kind, principal.att);

  if (kind === "agent" && tier === "pro") {
    const soft = config.quotas.pro.agent_soft;
    const row = await env.DB.prepare("SELECT count, last_at FROM usage_daily WHERE device_id = ? AND day = ? AND kind = ?")
      .bind(principal.sub, day, kind)
      .first<{ count: number; last_at: number }>();
    if (row && row.count >= soft && row.count < limit) {
      const wait = Math.ceil((row.last_at + config.agent_slow_down_seconds * 1000 - now) / 1000);
      if (wait > 0) {
        throw new HttpError(429, "slow_down", "Fair-use limit reached; please wait a moment", { kind, retry_after: wait }, {
          "retry-after": String(wait),
        });
      }
    }
  }

  const exceeded = () =>
    new HttpError(429, "quota_exceeded", "Daily limit reached", { kind, limit, tier, reset_at: nextUtcMidnight(now) });

  const subjects = [principal.sub];
  const charged = await increment(env, principal.sub, day, kind, limit, now);
  if (!charged) throw exceeded();

  if (!principal.att) {
    const ipSubject = `anonip:${request.headers.get("cf-connecting-ip") ?? "unknown"}`;
    const pooled = await increment(env, ipSubject, day, kind, limit * ANONYMOUS_IP_POOL_FACTOR, now);
    if (!pooled) {
      await refundQuota(env, { kind, subjects }, now);
      throw exceeded();
    }
    subjects.push(ipSubject);
  }

  return { kind, used: charged.count, limit, remaining: Math.max(0, limit - charged.count), subjects };
}

/** Gives back a unit after a failed or deduplicated generation. */
export async function refundQuota(env: Env, grant: Pick<QuotaGrant, "kind" | "subjects">, now = Date.now()) {
  const day = utcDay(now);
  await env.DB.batch(
    grant.subjects.map((subject) =>
      env.DB.prepare("UPDATE usage_daily SET count = MAX(0, count - 1) WHERE device_id = ? AND day = ? AND kind = ?").bind(
        subject,
        day,
        grant.kind,
      ),
    ),
  );
}

export async function usageToday(env: Env, deviceId: string, now = Date.now()): Promise<Record<string, number>> {
  const { results } = await env.DB.prepare("SELECT kind, count FROM usage_daily WHERE device_id = ? AND day = ?")
    .bind(deviceId, utcDay(now))
    .all<{ kind: string; count: number }>();
  return Object.fromEntries(results.map((r) => [r.kind, r.count]));
}

/** Global circuit breaker: once today's tokens exceed DAILY_TOKEN_BUDGET, new generations are refused. */
export async function assertBudget(env: Env, now = Date.now()): Promise<void> {
  const budget = intVar(env.DAILY_TOKEN_BUDGET, 0);
  if (budget <= 0) return;
  const row = await env.DB.prepare("SELECT tokens FROM budget_daily WHERE day = ?").bind(utcDay(now)).first<{ tokens: number }>();
  if (row && row.tokens >= budget) {
    throw new HttpError(503, "budget_exhausted", "AI is temporarily unavailable; please try again later");
  }
}

export async function recordTokens(env: Env, tokens: number, now = Date.now()): Promise<void> {
  if (!tokens || tokens <= 0) return;
  await env.DB.prepare(
    `INSERT INTO budget_daily (day, tokens) VALUES (?, ?)
     ON CONFLICT(day) DO UPDATE SET tokens = tokens + excluded.tokens`,
  )
    .bind(utcDay(now), Math.round(tokens))
    .run();
}
