import { HttpError } from "../http";

const DOMAIN = /^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/;
const ICON_TTL = 7 * 24 * 3600;
const MISSING_TTL = 24 * 3600;

/**
 * GET /api/v1/icon?d=example.com -> site icon (PNG), or 404 when the site has none.
 * Proxied and edge-cached so the feed's icons load where the upstream favicon service is unreachable (China).
 */
export async function handleIcon(request: Request, _env: unknown, ctx: ExecutionContext): Promise<Response> {
  const domain = (new URL(request.url).searchParams.get("d") ?? "").toLowerCase();
  if (!DOMAIN.test(domain)) throw new HttpError(400, "invalid_request", "d must be a domain name");

  const cacheKey = new Request(`https://icon.cache/${domain}`);
  const cache = caches.default;
  const hit = await cache.match(cacheKey);
  if (hit) return hit;

  let response: Response;
  try {
    const upstream = await fetch(`https://www.google.com/s2/favicons?domain=${domain}&sz=64`);
    const type = upstream.headers.get("content-type") ?? "";
    response = upstream.ok && type.startsWith("image/")
      ? new Response(upstream.body, { headers: { "content-type": type, "cache-control": `public, max-age=${ICON_TTL}` } })
      : new Response(null, { status: 404, headers: { "cache-control": `public, max-age=${MISSING_TTL}` } });
  } catch {
    return new Response(null, { status: 502, headers: { "cache-control": "no-store" } });
  }
  ctx.waitUntil(cache.put(cacheKey, response.clone()));
  return response;
}
