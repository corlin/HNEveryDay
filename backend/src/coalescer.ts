// One Durable Object instance per (kind, story, lang): concurrent cache misses for a hot story
// share a single in-flight generation instead of each calling the model.

import { DurableObject } from "cloudflare:workers";
import type { Env } from "./env";
import { HttpError } from "./http";
import { generateSummary, type SummaryJob, type SummaryResult } from "./generation";

export type CoalescedResult = { ok: true; value: SummaryResult } | { ok: false; status: number; code: string; message: string };

export class GenerationCoalescer extends DurableObject<Env> {
  private inflight: Promise<CoalescedResult> | null = null;

  async summary(job: SummaryJob): Promise<CoalescedResult> {
    if (this.inflight) {
      // Joined someone else's generation: report it as cached so the caller is not charged.
      return this.inflight.then((r): CoalescedResult => (r.ok ? { ok: true, value: { ...r.value, cached: true } } : r));
    }
    const run = generateSummary(this.env, job)
      .then((value): CoalescedResult => ({ ok: true, value }))
      .catch((error): CoalescedResult => {
        if (error instanceof HttpError) return { ok: false, status: error.status, code: error.code, message: error.message };
        console.error("summary generation failed", String(error));
        return { ok: false, status: 502, code: "upstream_error", message: "The AI provider is unavailable" };
      })
      .finally(() => {
        this.inflight = null;
      });
    this.inflight = run;
    return run;
  }
}

export async function coalescedSummary(env: Env, job: SummaryJob): Promise<SummaryResult> {
  const stub = env.COALESCER.get(env.COALESCER.idFromName(`summary:${job.storyId}:${job.lang}`));
  const result = await stub.summary(job);
  if (!result.ok) throw new HttpError(result.status, result.code, result.message);
  return result.value;
}
