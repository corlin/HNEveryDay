import type { Env } from "../env";
import { HttpError, json, optionalString, readJson, requireStoryId } from "../http";
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
