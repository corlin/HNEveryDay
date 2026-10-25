// Hacker News official Firebase API. The backend fetches titles and comments itself
// instead of trusting what the client sends.

import type { Env } from "./env";

const HN_API = "https://hacker-news.firebaseio.com/v0";

export interface HNItem {
  id: number;
  type?: string;
  by?: string;
  time?: number;
  title?: string;
  url?: string;
  text?: string;
  score?: number;
  descendants?: number;
  kids?: number[];
  deleted?: boolean;
  dead?: boolean;
}

export interface StoryRow {
  id: number;
  title: string;
  url: string | null;
  by: string | null;
  score: number;
  descendants: number;
  time: number;
}

export interface CommentText {
  by: string;
  text: string;
  depth: number;
}

export async function fetchItem(id: number): Promise<HNItem | null> {
  const response = await fetch(`${HN_API}/item/${id}.json`, { cf: { cacheTtl: 60 } } as RequestInit);
  if (!response.ok) return null;
  return (await response.json()) as HNItem | null;
}

export type StoryList = "top" | "new" | "best" | "ask" | "show";

export async function fetchStoryIds(list: StoryList, limit: number): Promise<number[]> {
  const response = await fetch(`${HN_API}/${list}stories.json`);
  if (!response.ok) return [];
  return ((await response.json()) as number[]).slice(0, limit);
}

function toStoryRow(item: HNItem): StoryRow | null {
  if (!item || item.deleted || item.dead || !item.title || !item.time) return null;
  return {
    id: item.id,
    title: item.title,
    url: item.url ?? null,
    by: item.by ?? null,
    score: item.score ?? 0,
    descendants: item.descendants ?? 0,
    time: item.time,
  };
}

export async function upsertStories(env: Env, stories: StoryRow[], now = Date.now()): Promise<void> {
  if (stories.length === 0) return;
  await env.DB.batch(
    stories.map((s) =>
      env.DB.prepare(
        `INSERT INTO stories (id, title, url, by, score, descendants, time, fetched_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET title = excluded.title, url = excluded.url, score = excluded.score,
           descendants = excluded.descendants, fetched_at = excluded.fetched_at`,
      ).bind(s.id, s.title, s.url, s.by, s.score, s.descendants, s.time, now),
    ),
  );
}

/** Returns stories from the hot window, fetching (and storing) any that are missing. */
export async function getStories(env: Env, ids: number[]): Promise<Map<number, StoryRow>> {
  const found = new Map<number, StoryRow>();
  if (ids.length === 0) return found;
  const placeholders = ids.map(() => "?").join(",");
  const { results } = await env.DB.prepare(
    `SELECT id, title, url, by, score, descendants, time FROM stories WHERE id IN (${placeholders})`,
  )
    .bind(...ids)
    .all<StoryRow>();
  for (const row of results) found.set(row.id, row);

  const missing = ids.filter((id) => !found.has(id));
  if (missing.length > 0) {
    const fetched = (await Promise.all(missing.map((id) => fetchItem(id).catch(() => null))))
      .map((item) => (item ? toStoryRow(item) : null))
      .filter((row): row is StoryRow => row !== null);
    await upsertStories(env, fetched);
    for (const row of fetched) found.set(row.id, row);
  }
  return found;
}

export async function getStory(env: Env, id: number): Promise<StoryRow | null> {
  return (await getStories(env, [id])).get(id) ?? null;
}

const ENTITIES: Record<string, string> = { "&quot;": '"', "&#x27;": "'", "&#39;": "'", "&gt;": ">", "&lt;": "<", "&#x2F;": "/" };

export function htmlToText(html: string): string {
  return html
    .replace(/<p>/gi, "\n\n")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&(quot|#x27|#39|gt|lt|#x2F);/g, (m) => ENTITIES[m] ?? m)
    .replace(/&amp;/g, "&")
    .trim();
}

/**
 * Collects discussion context in reading order: top-level comments first, then a couple of
 * replies under the earliest threads. Bounded by count and character budget.
 */
export async function fetchComments(
  story: Pick<HNItem, "kids">,
  options: { maxComments: number; maxCharsEach: number; maxCharsTotal: number; topLevel?: number; repliesPer?: number },
): Promise<CommentText[]> {
  const topLevel = options.topLevel ?? 20;
  const repliesPer = options.repliesPer ?? 2;
  const topIds = (story.kids ?? []).slice(0, topLevel);
  const tops = await Promise.all(topIds.map((id) => fetchItem(id).catch(() => null)));

  const replyIds: number[][] = tops.map((c, i) => (i < 10 && c?.kids ? c.kids.slice(0, repliesPer) : []));
  const replies = await Promise.all(
    replyIds.map((ids) => Promise.all(ids.map((id) => fetchItem(id).catch(() => null)))),
  );

  const out: CommentText[] = [];
  let total = 0;
  const push = (item: HNItem | null, depth: number) => {
    if (!item || item.deleted || item.dead || !item.text) return;
    if (out.length >= options.maxComments || total >= options.maxCharsTotal) return;
    const text = htmlToText(item.text).slice(0, options.maxCharsEach);
    total += text.length;
    out.push({ by: item.by ?? "unknown", text, depth });
  };
  tops.forEach((top, i) => {
    push(top, 0);
    for (const reply of replies[i]) push(reply, 1);
  });
  return out;
}

type CommentOptions = Parameters<typeof fetchComments>[1];
const DISCUSSION_TTL_SECONDS = 300;

/**
 * A story's comment digest, cached at the edge for a few minutes. Every Agent turn needs it, and
 * fetching ~40 items from Hacker News is the slowest step before the first token.
 */
export async function storyDiscussion(storyId: number, options: CommentOptions): Promise<CommentText[]> {
  const key = new Request(
    `https://cache.hneveryday.internal/discussion/${storyId}?m=${options.maxComments}&e=${options.maxCharsEach}&t=${options.maxCharsTotal}`,
  );
  const cache = (globalThis as { caches?: { default?: Cache } }).caches?.default;
  const hit = await cache?.match(key).catch(() => undefined);
  if (hit) return (await hit.json()) as CommentText[];

  const item = await fetchItem(storyId);
  const comments = item ? await fetchComments(item, options) : [];
  await cache
    ?.put(key, Response.json(comments, { headers: { "cache-control": `max-age=${DISCUSSION_TTL_SECONDS}` } }))
    .catch(() => {});
  return comments;
}
