// One Durable Object instance per (kind, story, lang): concurrent cache misses for a hot story
// share a single in-flight generation instead of each calling the model.

import { DurableObject } from "cloudflare:workers";
import type { Env } from "./env";
import { HttpError } from "./http";
import {
  generateArticleTranslation,
  generateSummary,
  type ArticleJob,
  type ArticleResult,
  type SummaryJob,
  type SummaryResult,
} from "./generation";

type Failure = { ok: false; status: number; code: string; message: string };
export type CoalescedResult<T> = { ok: true; value: T } | Failure;

export class GenerationCoalescer extends DurableObject<Env> {
  // Each instance serves one (kind, story, lang), so one in-flight slot is enough.
  private inflight: Promise<CoalescedResult<SummaryResult | ArticleResult>> | null = null;

  private coalesce<T extends { cached: boolean }>(generate: () => Promise<T>): Promise<CoalescedResult<T>> {
    if (this.inflight) {
      // Joined someone else's generation: report it as cached so the caller is not charged.
      return (this.inflight as Promise<CoalescedResult<T>>).then((r) => (r.ok ? { ok: true, value: { ...r.value, cached: true } } : r));
    }
    const run = generate()
      .then((value): CoalescedResult<T> => ({ ok: true, value }))
      .catch((error): CoalescedResult<T> => {
        if (error instanceof HttpError) return { ok: false, status: error.status, code: error.code, message: error.message };
        console.error("generation failed", String(error));
        return { ok: false, status: 502, code: "upstream_error", message: "The AI provider is unavailable" };
      })
      .finally(() => {
        this.inflight = null;
      });
    this.inflight = run as Promise<CoalescedResult<SummaryResult | ArticleResult>>;
    return run;
  }

  async summary(job: SummaryJob): Promise<CoalescedResult<SummaryResult>> {
    return this.coalesce(() => generateSummary(this.env, job));
  }

  async article(job: ArticleJob): Promise<CoalescedResult<ArticleResult>> {
    return this.coalesce(() => generateArticleTranslation(this.env, job));
  }
}

function unwrap<T>(result: CoalescedResult<T>): T {
  if (!result.ok) throw new HttpError(result.status, result.code, result.message);
  return result.value;
}

export async function coalescedSummary(env: Env, job: SummaryJob): Promise<SummaryResult> {
  const stub = env.COALESCER.get(env.COALESCER.idFromName(`summary:${job.storyId}:${job.lang}`));
  return unwrap((await stub.summary(job)) as CoalescedResult<SummaryResult>);
}

export async function coalescedArticle(env: Env, job: ArticleJob & { storyId: number }): Promise<ArticleResult> {
  const stub = env.COALESCER.get(env.COALESCER.idFromName(`article:${job.storyId}:${job.lang}`));
  return unwrap((await stub.article(job)) as CoalescedResult<ArticleResult>);
}
