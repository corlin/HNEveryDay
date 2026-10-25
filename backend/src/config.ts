import type { Env } from "./env";
import { listVar } from "./env";
import { HttpError } from "./http";

export type Tier = "free" | "pro";
export type QuotaKind = "summary" | "article" | "agent";
export type Feature = "hosted_ai" | "summary" | "article_translation" | "agent" | "paywall";

export interface TierQuotas {
  summary: number;
  article: number;
  /** Hard daily cap of Agent turns. */
  agent: number;
  /** Turns at normal speed; beyond this Pro users are slowed down until the hard cap. */
  agent_soft: number;
}

export interface RemoteConfig {
  features: Record<Feature, boolean>;
  min_app_version: string;
  disabled_countries: string[];
  quotas: Record<Tier, TierQuotas>;
  /** Quota multiplier for devices without App Attest (anonymous tokens). */
  anonymous_quota_factor: number;
  agent_slow_down_seconds: number;
  products: string[];
  notice: string | null;
}

export function defaultConfig(env: Env): RemoteConfig {
  return {
    features: { hosted_ai: true, summary: true, article_translation: true, agent: true, paywall: true },
    min_app_version: "1.2.0",
    // Hosted generative AI stays off in mainland China until the filing question is settled (spec §10).
    disabled_countries: ["CN"],
    quotas: {
      free: { summary: 10, article: 3, agent: 3, agent_soft: 3 },
      pro: { summary: 200, article: 50, agent: 200, agent_soft: 50 },
    },
    anonymous_quota_factor: 0.5,
    agent_slow_down_seconds: 120,
    products: listVar(env.PRO_PRODUCT_IDS),
    notice: null,
  };
}

const CACHE_TTL_MS = 60_000;
let cached: { at: number; value: RemoteConfig } | null = null;

/** Defaults merged with the JSON stored under KV key "config" (one level deep). */
export async function loadConfig(env: Env): Promise<RemoteConfig> {
  if (cached && Date.now() - cached.at < CACHE_TTL_MS) return cached.value;
  const base = defaultConfig(env);
  let override: Partial<RemoteConfig> | null = null;
  try {
    override = await env.CONFIG.get<Partial<RemoteConfig>>("config", "json");
  } catch {
    override = null;
  }
  const merged: RemoteConfig = {
    ...base,
    ...override,
    features: { ...base.features, ...override?.features },
    quotas: {
      free: { ...base.quotas.free, ...override?.quotas?.free },
      pro: { ...base.quotas.pro, ...override?.quotas?.pro },
    },
  };
  cached = { at: Date.now(), value: merged };
  return merged;
}

export function resetConfigCache(): void {
  cached = null;
}

export function compareVersions(a: string, b: string): number {
  const pa = a.split(".").map((n) => Number.parseInt(n, 10) || 0);
  const pb = b.split(".").map((n) => Number.parseInt(n, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const diff = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (diff !== 0) return Math.sign(diff);
  }
  return 0;
}

/** Throws 503 when a hosted feature is switched off, the app is too old, or the region is disabled. */
export function assertFeatureEnabled(config: RemoteConfig, feature: Feature, request: Request): void {
  if (!config.features.hosted_ai || !config.features[feature]) {
    throw new HttpError(503, "feature_disabled", "This feature is temporarily unavailable", { feature });
  }
  const appVersion = request.headers.get("x-app-version");
  if (appVersion && compareVersions(appVersion, config.min_app_version) < 0) {
    throw new HttpError(503, "upgrade_required", "Please update the app to use this feature", {
      min_app_version: config.min_app_version,
    });
  }
  const country = (request as Request & { cf?: { country?: string } }).cf?.country;
  if (country && config.disabled_countries.includes(country)) {
    throw new HttpError(503, "region_unavailable", "This feature is not available in your region", { feature });
  }
}
