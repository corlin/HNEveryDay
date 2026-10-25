import { loadConfig } from "./config";
import { runScheduled } from "./cron";
import type { Env } from "./env";
import { errorResponse, HttpError, json } from "./http";
import { handleTakedown } from "./routes/admin";
import {
  handleAgentChat,
  handleAgentQuestions,
  handleMe,
  handleReport,
  handleSummary,
  handleTranslateArticle,
  handleTranslateTitles,
} from "./routes/ai";
import { handleAnonymous, handleAssert, handleAttest, handleChallenge } from "./routes/auth";
import { handleAppStoreNotification, handleVerifySubscription } from "./routes/subscription";

export { GenerationCoalescer } from "./coalescer";

type Handler = (request: Request, env: Env, ctx: ExecutionContext) => Promise<Response>;

const routes: Record<string, Handler> = {
  "GET /api/v1/config": async (_request, env) => json(await loadConfig(env), 200, { "cache-control": "public, max-age=300" }),
  "POST /api/v1/auth/challenge": handleChallenge,
  "POST /api/v1/auth/attest": handleAttest,
  "POST /api/v1/auth/assert": handleAssert,
  "POST /api/v1/auth/anonymous": handleAnonymous,
  "POST /api/v1/translate/titles": handleTranslateTitles,
  "POST /api/v1/translate/article": handleTranslateArticle,
  "POST /api/v1/summary": handleSummary,
  "POST /api/v1/agent/chat": handleAgentChat,
  "POST /api/v1/agent/questions": handleAgentQuestions,
  "GET /api/v1/me": handleMe,
  "POST /api/v1/report": handleReport,
  "POST /api/v1/subscription/verify": handleVerifySubscription,
  "POST /api/v1/appstore/notifications": handleAppStoreNotification,
  "POST /api/v1/admin/takedown": handleTakedown,
};

export default {
  async fetch(request, env, ctx): Promise<Response> {
    const url = new URL(request.url);
    const handler = routes[`${request.method} ${url.pathname}`];
    try {
      if (!handler) {
        if (url.pathname === "/health") return json({ ok: true });
        throw new HttpError(404, "not_found", "Not found");
      }
      return await handler(request, env, ctx);
    } catch (error) {
      if (error instanceof HttpError) return errorResponse(error);
      console.error("unhandled error", error instanceof Error ? error.stack : String(error));
      return errorResponse(new HttpError(500, "internal_error", "Internal error"));
    }
  },

  async scheduled(_controller, env, ctx): Promise<void> {
    ctx.waitUntil(runScheduled(env));
  },
} satisfies ExportedHandler<Env>;
