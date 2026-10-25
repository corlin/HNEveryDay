import type { Env } from "./env";
import { PROMPT_VERSIONS, type OutputKind } from "./prompts";

export async function getOutputs(env: Env, kind: OutputKind, lang: string, storyIds: number[]): Promise<Map<number, string>> {
  const out = new Map<number, string>();
  if (storyIds.length === 0) return out;
  const placeholders = storyIds.map(() => "?").join(",");
  const { results } = await env.DB.prepare(
    `SELECT story_id, content FROM ai_outputs
     WHERE kind = ? AND lang = ? AND prompt_version = ? AND model = ? AND story_id IN (${placeholders})
       AND story_id NOT IN (SELECT story_id FROM blocked_stories)`,
  )
    .bind(kind, lang, PROMPT_VERSIONS[kind], env.LLM_MODEL, ...storyIds)
    .all<{ story_id: number; content: string }>();
  for (const row of results) out.set(row.story_id, row.content);
  return out;
}

export async function getOutput(env: Env, kind: OutputKind, lang: string, storyId: number): Promise<string | null> {
  return (await getOutputs(env, kind, lang, [storyId])).get(storyId) ?? null;
}

export async function putOutputs(env: Env, kind: OutputKind, lang: string, entries: Map<number, string>, now = Date.now()) {
  if (entries.size === 0) return;
  await env.DB.batch(
    [...entries].map(([storyId, content]) =>
      env.DB.prepare(
        `INSERT OR REPLACE INTO ai_outputs (story_id, kind, lang, prompt_version, model, content, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
      ).bind(storyId, kind, lang, PROMPT_VERSIONS[kind], env.LLM_MODEL, content, now),
    ),
  );
}

export async function blockedAmong(env: Env, storyIds: number[]): Promise<Set<number>> {
  if (storyIds.length === 0) return new Set();
  const placeholders = storyIds.map(() => "?").join(",");
  const { results } = await env.DB.prepare(`SELECT story_id FROM blocked_stories WHERE story_id IN (${placeholders})`)
    .bind(...storyIds)
    .all<{ story_id: number }>();
  return new Set(results.map((r) => r.story_id));
}
