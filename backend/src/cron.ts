import type { Env } from "./env";
import { listVar } from "./env";
import { agentQuestions, translateTitles } from "./generation";
import { HttpError } from "./http";
import { fetchStoryIds, getStories, type StoryList, type StoryRow } from "./hn";
import { getOutputs } from "./outputs";
import { isSupportedLanguage, PROMPT_VERSIONS } from "./prompts";
import { utcDay } from "./quota";

const DAY_MS = 24 * 60 * 60 * 1000;
export const HOT_WINDOW_DAYS = 30;
const STALE_OUTPUT_DAYS = 90;
const USAGE_RETENTION_DAYS = 7;

/** Moves stories older than the hot window into the minimal archive. AI outputs are untouched. */
export async function archiveExpiredStories(env: Env, now = Date.now()): Promise<number> {
  const cutoff = Math.floor((now - HOT_WINDOW_DAYS * DAY_MS) / 1000);
  const [, deleted] = await env.DB.batch([
    env.DB.prepare(
      `INSERT OR REPLACE INTO story_archive (id, title, url, time, final_score)
       SELECT id, title, url, time, score FROM stories WHERE time < ?`,
    ).bind(cutoff),
    env.DB.prepare("DELETE FROM stories WHERE time < ?").bind(cutoff),
  ]);
  return deleted.meta.changes ?? 0;
}

/** Deletes outputs produced by an older prompt version or model once they are 90 days old. */
export async function cleanupStaleOutputs(env: Env, now = Date.now()): Promise<void> {
  const cutoff = now - STALE_OUTPUT_DAYS * DAY_MS;
  await env.DB.batch([
    ...Object.entries(PROMPT_VERSIONS).map(([kind, version]) =>
      env.DB.prepare(
        "DELETE FROM ai_outputs WHERE kind = ? AND (prompt_version <> ? OR model <> ?) AND created_at < ?",
      ).bind(kind, version, env.LLM_MODEL, cutoff),
    ),
    env.DB.prepare("DELETE FROM usage_daily WHERE day < ?").bind(utcDay(now - USAGE_RETENTION_DAYS * DAY_MS)),
    env.DB.prepare("DELETE FROM budget_daily WHERE day < ?").bind(utcDay(now - 90 * DAY_MS)),
    env.DB.prepare("DELETE FROM attest_challenges WHERE expires_at < ?").bind(now),
  ]);
}

/**
 * What the hourly cron pre-processes. Titles are cheap (~30 tokens each), so every list a reader is
 * likely to scroll gets them. Agent questions cost ~2k tokens, so only stories that already have a
 * real discussion get them, busiest first. "new" is left to on-demand requests: it churns every few
 * minutes and most of its stories never get traction. Summaries are never prewarmed: the server has
 * no article text, and a comment-only summary would be cached for everyone.
 */
export const PREWARM_PLAN = {
  titles: { top: 30, best: 30, ask: 15, show: 15 } as Partial<Record<StoryList, number>>,
  questions: {
    /** Minimum comment count per list; Ask HN is discussion by nature, so its bar is lower. */
    minComments: { top: 20, best: 20, ask: 10 } as Partial<Record<StoryList, number>>,
    perRun: 10,
  },
};

/** Pulls the configured lists into the hot window, pre-translates titles and pre-generates Agent questions. */
export async function prewarm(env: Env): Promise<void> {
  const lists = Object.entries(PREWARM_PLAN.titles) as [StoryList, number][];
  const fetched = await Promise.all(lists.map(([list, limit]) => fetchStoryIds(list, limit).catch(() => [])));
  const byList = new Map(lists.map(([list], i) => [list, fetched[i]]));
  const ids = [...new Set(fetched.flat())];
  if (ids.length === 0) return;
  const stories = await getStories(env, ids);

  const langs = listVar(env.PREWARM_LANGS).filter(isSupportedLanguage);
  for (const lang of langs) {
    for (let i = 0; i < ids.length; i += 30) await translateTitles(env, ids.slice(i, i + 30), lang, "cron");
  }
  await prewarmAgentQuestions(env, selectQuestionCandidates(byList, stories), langs);
}

/** Stories worth pre-generating questions for, busiest discussion first. */
export function selectQuestionCandidates(byList: Map<StoryList, number[]>, stories: Map<number, StoryRow>): number[] {
  const picked = new Set<number>();
  for (const [list, minComments] of Object.entries(PREWARM_PLAN.questions.minComments) as [StoryList, number][]) {
    for (const id of byList.get(list) ?? []) {
      if ((stories.get(id)?.descendants ?? 0) >= minComments) picked.add(id);
    }
  }
  return [...picked].sort((a, b) => (stories.get(b)?.descendants ?? 0) - (stories.get(a)?.descendants ?? 0));
}

/** Generates missing questions for `candidates` (in order), at most PREWARM_PLAN.questions.perRun per run. */
export async function prewarmAgentQuestions(env: Env, candidates: number[], langs: string[]): Promise<number> {
  let generated = 0;
  for (const lang of langs) {
    const existing = await getOutputs(env, "questions", lang, candidates);
    for (const id of candidates) {
      if (existing.has(id)) continue;
      if (generated >= PREWARM_PLAN.questions.perRun) return generated;
      try {
        await agentQuestions(env, id, lang, undefined, "cron");
        generated++;
      } catch (error) {
        console.warn("question prewarm failed", id, String(error));
        if (error instanceof HttpError && error.code === "budget_exhausted") return generated;
      }
    }
  }
  return generated;
}

export async function runScheduled(env: Env): Promise<void> {
  const steps: [string, () => Promise<unknown>][] = [
    ["archive", () => archiveExpiredStories(env)],
    ["cleanup", () => cleanupStaleOutputs(env)],
    ["prewarm", () => prewarm(env)],
  ];
  for (const [name, step] of steps) {
    try {
      await step();
    } catch (error) {
      console.error(`cron step ${name} failed`, String(error));
    }
  }
}
