import type { Env } from "./env";
import { listVar } from "./env";
import { translateTitles } from "./generation";
import { fetchTopStoryIds, getStories } from "./hn";
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

/** Pulls the current front page into the hot window and pre-translates its titles. */
export async function prewarm(env: Env): Promise<void> {
  const ids = await fetchTopStoryIds(30);
  if (ids.length === 0) return;
  await getStories(env, ids);
  for (const lang of listVar(env.PREWARM_LANGS).filter(isSupportedLanguage)) {
    await translateTitles(env, ids, lang);
  }
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
