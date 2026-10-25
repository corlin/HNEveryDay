import { authenticate } from "../auth/token";
import { coalescedSummary } from "../coalescer";
import { assertFeatureEnabled, loadConfig } from "../config";
import type { Env } from "../env";
import { HttpError, json, optionalString, readJson, requireStoryId, requireString } from "../http";
import { fetchComments, fetchItem, getStory } from "../hn";
import { chatCompletion, openChatStream, parseChatStream, type ChatMessage } from "../llm";
import { blockedAmong, getOutput } from "../outputs";
import { AGENT_MAX_HISTORY, agentSystemPrompt, articleTranslationMessages, isSupportedLanguage } from "../prompts";
import { assertBudget, consumeQuota, recordTokens, refundQuota, resolveTier, usageToday, quotaLimit } from "../quota";
import { translateTitles } from "../generation";

function requireLanguage(value: unknown): string {
  if (!isSupportedLanguage(value)) throw new HttpError(400, "unsupported_language", "lang is not supported");
  return value;
}

async function assertNotBlocked(env: Env, storyId: number) {
  if ((await blockedAmong(env, [storyId])).size > 0) {
    throw new HttpError(451, "story_unavailable", "AI content for this story has been removed");
  }
}

/** POST /api/v1/translate/titles { lang, ids[] } -> { translations: { [id]: title }, missing: id[] } */
export async function handleTranslateTitles(request: Request, env: Env): Promise<Response> {
  const config = await loadConfig(env);
  assertFeatureEnabled(config, "hosted_ai", request);
  await authenticate(request, env);
  const body = await readJson<{ lang?: unknown; ids?: unknown }>(request);
  const lang = requireLanguage(body.lang);
  if (!Array.isArray(body.ids) || body.ids.length === 0 || body.ids.length > 50) {
    throw new HttpError(400, "invalid_request", "ids must contain 1-50 story ids");
  }
  const ids = [...new Set(body.ids.map((id) => requireStoryId(id, "ids[]")))];
  const blocked = await blockedAmong(env, ids);
  const allowed = ids.filter((id) => !blocked.has(id));
  const translations = await translateTitles(env, allowed, lang);
  return json({
    translations: Object.fromEntries(translations),
    missing: ids.filter((id) => !translations.has(id)),
  });
}

/** POST /api/v1/summary { story_id, lang, article_text? } -> { summary, cached, quota? } */
export async function handleSummary(request: Request, env: Env): Promise<Response> {
  const config = await loadConfig(env);
  assertFeatureEnabled(config, "summary", request);
  const principal = await authenticate(request, env);
  const body = await readJson<Record<string, unknown>>(request);
  const storyId = requireStoryId(body.story_id);
  const lang = requireLanguage(body.lang);
  const articleText = optionalString(body.article_text, "article_text", 12_000);
  await assertNotBlocked(env, storyId);

  const cached = await getOutput(env, "summary", lang, storyId);
  if (cached) return json({ summary: cached, cached: true });

  const tier = await resolveTier(env, principal.sub);
  const grant = await consumeQuota(env, request, principal, tier, "summary", config);
  try {
    const result = await coalescedSummary(env, { storyId, lang, articleText });
    // Someone else's in-flight generation served us: do not charge for it.
    if (result.cached) await refundQuota(env, grant);
    const remaining = result.cached ? grant.remaining + 1 : grant.remaining;
    return json({ summary: result.summary, cached: result.cached, quota: { kind: "summary", limit: grant.limit, remaining } });
  } catch (error) {
    await refundQuota(env, grant);
    throw error;
  }
}

/** POST /api/v1/translate/article { story_id?, title, lang, article_text } -> { title, markdown }. Never cached server-side. */
export async function handleTranslateArticle(request: Request, env: Env): Promise<Response> {
  const config = await loadConfig(env);
  assertFeatureEnabled(config, "article_translation", request);
  const principal = await authenticate(request, env);
  const body = await readJson<Record<string, unknown>>(request);
  const lang = requireLanguage(body.lang);
  const title = requireString(body.title, "title", 500);
  const articleText = requireString(body.article_text, "article_text", 40_000).slice(0, 8000);
  if (body.story_id !== undefined) await assertNotBlocked(env, requireStoryId(body.story_id));
  await assertBudget(env);

  const tier = await resolveTier(env, principal.sub);
  const grant = await consumeQuota(env, request, principal, tier, "article", config);
  try {
    const completion = await chatCompletion(env, articleTranslationMessages(title, articleText, lang), {
      temperature: 0.2,
      maxTokens: 4000,
      json: true,
    });
    await recordTokens(env, completion.totalTokens);
    const start = completion.content.indexOf("{");
    const end = completion.content.lastIndexOf("}");
    const parsed = JSON.parse(completion.content.slice(start, end + 1)) as { translated_title?: string; translated_markdown?: string };
    if (!parsed.translated_title || !parsed.translated_markdown) throw new Error("malformed translation");
    return json({
      title: parsed.translated_title,
      markdown: parsed.translated_markdown,
      quota: { kind: "article", limit: grant.limit, remaining: grant.remaining },
    });
  } catch (error) {
    await refundQuota(env, grant);
    if (error instanceof HttpError) throw error;
    throw new HttpError(502, "upstream_error", "Translation failed");
  }
}

function sse(event: string, data: unknown): Uint8Array {
  return new TextEncoder().encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
}

function sanitizeHistory(value: unknown): ChatMessage[] {
  if (!Array.isArray(value) || value.length === 0) throw new HttpError(400, "invalid_request", "messages is required");
  const messages = value.slice(-AGENT_MAX_HISTORY).map((m) => {
    const role = (m as { role?: unknown })?.role;
    const content = (m as { content?: unknown })?.content;
    if ((role !== "user" && role !== "assistant") || typeof content !== "string" || !content.trim()) {
      throw new HttpError(400, "invalid_request", "messages must be user/assistant text");
    }
    return { role, content: content.slice(0, role === "user" ? 2000 : 6000) } as ChatMessage;
  });
  if (messages[messages.length - 1].role !== "user") throw new HttpError(400, "invalid_request", "last message must be from the user");
  return messages;
}

/**
 * POST /api/v1/agent/chat { story_id, lang, messages[], article_text? } -> text/event-stream.
 * The turn is charged when it starts; an interrupted stream is not refunded (spec §5).
 */
export async function handleAgentChat(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  const config = await loadConfig(env);
  assertFeatureEnabled(config, "agent", request);
  const principal = await authenticate(request, env);
  const body = await readJson<Record<string, unknown>>(request, 128 * 1024);
  const storyId = requireStoryId(body.story_id);
  const lang = requireLanguage(body.lang);
  const history = sanitizeHistory(body.messages);
  const articleText = optionalString(body.article_text, "article_text", 12_000);
  await assertNotBlocked(env, storyId);
  await assertBudget(env);

  const story = await getStory(env, storyId);
  if (!story) throw new HttpError(404, "story_not_found", "Story not found");

  const tier = await resolveTier(env, principal.sub);
  const grant = await consumeQuota(env, request, principal, tier, "agent", config);

  let upstream: ReadableStream<Uint8Array>;
  try {
    const item = await fetchItem(storyId);
    const comments = item ? await fetchComments(item, { maxComments: 40, maxCharsEach: 600, maxCharsTotal: 24_000 }) : [];
    upstream = await openChatStream(env, [{ role: "system", content: agentSystemPrompt(story, comments, articleText, lang) }, ...history], {
      temperature: 0.4,
      maxTokens: 1500,
      signal: request.signal,
    });
  } catch (error) {
    await refundQuota(env, grant);
    throw error;
  }

  const { readable, writable } = new TransformStream<Uint8Array, Uint8Array>();
  const writer = writable.getWriter();
  const pump = async () => {
    let tokens = 0;
    let produced = 0;
    try {
      await writer.write(sse("meta", { tier, remaining: grant.remaining, limit: grant.limit }));
      for await (const chunk of parseChatStream(upstream)) {
        if (chunk.text) {
          produced += chunk.text.length;
          await writer.write(sse("delta", { text: chunk.text }));
        }
        if (chunk.totalTokens) tokens = chunk.totalTokens;
        if (chunk.finishReason) await writer.write(sse("done", { finish_reason: chunk.finishReason }));
      }
    } catch (error) {
      console.warn("agent stream ended early", String(error));
      await writer.write(sse("error", { code: "upstream_error", message: "The AI provider stopped responding" })).catch(() => {});
    } finally {
      await recordTokens(env, tokens || Math.ceil(produced / 4) + 8000).catch(() => {});
      await writer.close().catch(() => {});
    }
  };
  ctx.waitUntil(pump());

  return new Response(readable, {
    headers: { "content-type": "text/event-stream; charset=utf-8", "cache-control": "no-store", "x-accel-buffering": "no" },
  });
}

/** GET /api/v1/me -> tier, subscription and today's usage. */
export async function handleMe(request: Request, env: Env): Promise<Response> {
  const config = await loadConfig(env);
  const principal = await authenticate(request, env);
  const tier = await resolveTier(env, principal.sub);
  const usage = await usageToday(env, principal.sub);
  const sub = await env.DB.prepare(
    `SELECT s.product_id, s.status, s.expires_at, s.auto_renew FROM subscription_devices d
     JOIN subscriptions s ON s.original_transaction_id = d.original_transaction_id
     WHERE d.device_id = ? ORDER BY s.expires_at DESC LIMIT 1`,
  )
    .bind(principal.sub)
    .first<{ product_id: string; status: string; expires_at: number; auto_renew: number | null }>();
  const kinds = ["summary", "article", "agent"] as const;
  return json({
    device_id: principal.sub,
    attested: principal.att,
    tier,
    subscription: sub
      ? { product_id: sub.product_id, status: sub.status, expires_at: sub.expires_at, auto_renew: sub.auto_renew === 1 }
      : null,
    quotas: Object.fromEntries(
      kinds.map((kind) => {
        const limit = quotaLimit(config, tier, kind, principal.att);
        const used = usage[kind] ?? 0;
        return [kind, { limit, used, remaining: Math.max(0, limit - used) }];
      }),
    ),
  });
}

/** POST /api/v1/report { story_id, kind, reason? } */
export async function handleReport(request: Request, env: Env): Promise<Response> {
  const principal = await authenticate(request, env);
  const body = await readJson<Record<string, unknown>>(request, 8 * 1024);
  const storyId = requireStoryId(body.story_id);
  const kind = requireString(body.kind, "kind", 32);
  if (!["title", "summary", "article", "agent"].includes(kind)) throw new HttpError(400, "invalid_request", "unknown kind");
  const reason = optionalString(body.reason, "reason", 1000) ?? null;
  await env.DB.prepare("INSERT INTO reports (device_id, story_id, kind, reason, created_at) VALUES (?, ?, ?, ?, ?)")
    .bind(principal.sub, storyId, kind, reason, Date.now())
    .run();
  return json({ ok: true }, 202);
}
