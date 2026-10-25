export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly extra: Record<string, unknown> = {},
    readonly headers: Record<string, string> = {},
  ) {
    super(message);
  }
}

export function json(body: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...headers },
  });
}

export function errorResponse(error: HttpError): Response {
  return json({ error: { code: error.code, message: error.message, ...error.extra } }, error.status, error.headers);
}

export async function readJson<T>(request: Request, maxBytes = 256 * 1024): Promise<T> {
  const length = Number(request.headers.get("content-length") ?? "0");
  if (length > maxBytes) throw new HttpError(413, "payload_too_large", "Request body is too large");
  const text = await request.text();
  if (text.length > maxBytes) throw new HttpError(413, "payload_too_large", "Request body is too large");
  try {
    return JSON.parse(text) as T;
  } catch {
    throw new HttpError(400, "invalid_json", "Request body must be JSON");
  }
}

export function requireString(value: unknown, name: string, maxLength = 1000): string {
  if (typeof value !== "string" || value.length === 0) throw new HttpError(400, "invalid_request", `${name} is required`);
  if (value.length > maxLength) throw new HttpError(400, "invalid_request", `${name} is too long`);
  return value;
}

export function optionalString(value: unknown, name: string, maxLength: number): string | undefined {
  if (value === undefined || value === null || value === "") return undefined;
  if (typeof value !== "string") throw new HttpError(400, "invalid_request", `${name} must be a string`);
  return value.slice(0, maxLength);
}

export function requireStoryId(value: unknown, name = "story_id"): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value <= 0) {
    throw new HttpError(400, "invalid_request", `${name} must be a positive integer`);
  }
  return value;
}
