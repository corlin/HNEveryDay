import type { GenerationCoalescer } from "./coalescer";

/** Subset of the Cloudflare Rate Limiting binding we use. */
export interface RateLimiter {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

export interface Env {
  DB: D1Database;
  CONFIG: KVNamespace;
  COALESCER: DurableObjectNamespace<GenerationCoalescer>;
  DEVICE_LIMITER?: RateLimiter;
  IP_LIMITER?: RateLimiter;

  APP_TEAM_ID: string;
  APP_BUNDLE_ID: string;
  ATTEST_MODE: "off" | "soft" | "enforce";
  ALLOW_DEV_ATTEST: string;
  ALLOW_SANDBOX: string;
  LLM_BASE_URL: string;
  LLM_MODEL: string;
  DAILY_TOKEN_BUDGET: string;
  PREWARM_LANGS: string;
  MAX_DEVICES_PER_SUBSCRIPTION: string;
  PRO_PRODUCT_IDS: string;

  LLM_API_KEY: string;
  TOKEN_SECRET: string;
  ADMIN_TOKEN?: string;
  ASC_KEY_ID?: string;
  ASC_ISSUER_ID?: string;
  ASC_PRIVATE_KEY?: string;
}

export function flag(value: string | undefined): boolean {
  return value === "true" || value === "1";
}

export function intVar(value: string | undefined, fallback: number): number {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function listVar(value: string | undefined): string[] {
  return (value ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
}
