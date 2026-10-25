import type { Env } from "../env";
import { intVar } from "../env";
import { HttpError, json, optionalString, readJson, requireStoryId } from "../http";
import { utcDay } from "../quota";
import { bytesEqual, utf8 } from "../util/bytes";

function assertAdmin(request: Request, env: Env) {
  const provided = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!env.ADMIN_TOKEN || !bytesEqual(utf8(provided), utf8(env.ADMIN_TOKEN))) {
    throw new HttpError(401, "unauthorized", "Admin token required");
  }
}

/** POST /api/v1/admin/takedown { story_id, reason? } — removes and blocks all AI outputs for a story. */
export async function handleTakedown(request: Request, env: Env): Promise<Response> {
  assertAdmin(request, env);
  const body = await readJson<Record<string, unknown>>(request, 4 * 1024);
  const storyId = requireStoryId(body.story_id);
  const reason = optionalString(body.reason, "reason", 500) ?? null;
  await env.DB.batch([
    env.DB.prepare("INSERT OR REPLACE INTO blocked_stories (story_id, reason, created_at) VALUES (?, ?, ?)").bind(storyId, reason, Date.now()),
    env.DB.prepare("DELETE FROM ai_outputs WHERE story_id = ?").bind(storyId),
  ]);
  return json({ ok: true, story_id: storyId });
}

/** Model prices per million tokens, stored in KV under "pricing" (see backend/README.md). */
export interface Pricing {
  currency: string;
  input_per_million: number;
  cached_input_per_million: number;
  output_per_million: number;
}

interface UsageRow {
  day: string;
  feature: string;
  source: string;
  calls: number;
  input_tokens: number;
  cached_input_tokens: number;
  output_tokens: number;
}

export function estimateCost(row: Pick<UsageRow, "input_tokens" | "cached_input_tokens" | "output_tokens">, pricing: Pricing | null): number | null {
  if (!pricing) return null;
  const uncached = Math.max(0, row.input_tokens - row.cached_input_tokens);
  const cost =
    (uncached * pricing.input_per_million +
      row.cached_input_tokens * pricing.cached_input_per_million +
      row.output_tokens * pricing.output_per_million) /
    1_000_000;
  return Math.round(cost * 10_000) / 10_000;
}

async function loadPricing(env: Env): Promise<Pricing | null> {
  const value = await env.CONFIG.get<Partial<Pricing>>("pricing", "json").catch(() => null);
  if (
    !value ||
    typeof value.input_per_million !== "number" ||
    typeof value.output_per_million !== "number"
  ) {
    return null;
  }
  return {
    currency: value.currency ?? "CNY",
    input_per_million: value.input_per_million,
    cached_input_per_million: value.cached_input_per_million ?? value.input_per_million,
    output_per_million: value.output_per_million,
  };
}

/**
 * GET /api/v1/admin/usage?days=14 — daily token use by feature and source (user vs cron), estimated
 * cost, today's share of the budget, cache size and active devices.
 */
export async function handleUsage(request: Request, env: Env): Promise<Response> {
  assertAdmin(request, env);
  const days = Math.min(90, Math.max(1, Number.parseInt(new URL(request.url).searchParams.get("days") ?? "14", 10) || 14));
  const since = utcDay(Date.now() - (days - 1) * 86_400_000);
  const pricing = await loadPricing(env);

  const [usage, budgets, cache, devices] = await Promise.all([
    env.DB.prepare("SELECT * FROM token_usage_daily WHERE day >= ? ORDER BY day DESC, feature, source").bind(since).all<UsageRow>(),
    env.DB.prepare("SELECT day, tokens FROM budget_daily WHERE day >= ? ORDER BY day DESC").bind(since).all<{ day: string; tokens: number }>(),
    env.DB.prepare("SELECT kind, lang, COUNT(*) AS count FROM ai_outputs GROUP BY kind, lang ORDER BY kind, lang").all<{ kind: string; lang: string; count: number }>(),
    env.DB.prepare(
      `SELECT day, COUNT(DISTINCT device_id) AS devices,
              SUM(CASE WHEN kind = 'summary' THEN count ELSE 0 END) AS summary,
              SUM(CASE WHEN kind = 'article' THEN count ELSE 0 END) AS article,
              SUM(CASE WHEN kind = 'agent' THEN count ELSE 0 END) AS agent
       FROM usage_daily WHERE device_id NOT LIKE 'anonip:%' GROUP BY day ORDER BY day DESC`,
    ).all<{ day: string; devices: number; summary: number; article: number; agent: number }>(),
  ]);

  const byDay = new Map<string, UsageRow[]>();
  for (const row of usage.results) byDay.set(row.day, [...(byDay.get(row.day) ?? []), row]);
  const totals = new Map(budgets.results.map((b) => [b.day, b.tokens]));
  const dayList = [...new Set([...totals.keys(), ...byDay.keys()])].sort().reverse();

  const budget = intVar(env.DAILY_TOKEN_BUDGET, 0);
  const today = totals.get(utcDay(Date.now())) ?? 0;
  return json({
    budget: { daily_tokens: budget, today_tokens: today, today_ratio: budget > 0 ? Math.round((today / budget) * 1000) / 1000 : null },
    pricing,
    days: dayList.map((day) => {
      const rows = byDay.get(day) ?? [];
      const features = rows.map((row) => ({ ...row, est_cost: estimateCost(row, pricing) }));
      const costs = features.map((f) => f.est_cost);
      return {
        day,
        tokens: totals.get(day) ?? 0,
        est_cost: pricing ? Math.round(costs.reduce((a: number, c) => a + (c ?? 0), 0) * 10_000) / 10_000 : null,
        features,
      };
    }),
    cache: cache.results,
    devices: devices.results,
  });
}
