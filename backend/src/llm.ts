// OpenAI-compatible chat completions client for the hosted model provider.

import type { Env } from "./env";
import { HttpError } from "./http";

export interface ChatMessage {
  role: "system" | "user" | "assistant";
  content: string;
}

export interface CompletionResult {
  content: string;
  totalTokens: number;
}

function endpoint(env: Env): string {
  return `${env.LLM_BASE_URL.replace(/\/+$/, "")}/chat/completions`;
}

function headers(env: Env): HeadersInit {
  return { authorization: `Bearer ${env.LLM_API_KEY}`, "content-type": "application/json" };
}

/** DeepSeek rejects prompts its content-safety filter flags with HTTP 400 "Content Exists Risk". */
export function isContentRisk(status: number, body: string): boolean {
  return status === 400 && /content exists risk|content_filter/i.test(body);
}

function contentBlocked(): HttpError {
  return new HttpError(422, "content_blocked", "This content can't be processed by the AI service");
}

/** Rough fallback when the provider omits usage: ~4 characters per token. */
export function estimateTokens(text: string): number {
  return Math.ceil(text.length / 4);
}

export async function chatCompletion(
  env: Env,
  messages: ChatMessage[],
  options: { temperature: number; maxTokens: number; json?: boolean },
): Promise<CompletionResult> {
  const body = JSON.stringify({
    model: env.LLM_MODEL,
    messages,
    temperature: options.temperature,
    max_tokens: options.maxTokens,
    ...(options.json ? { response_format: { type: "json_object" } } : {}),
  });

  let lastError: unknown;
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const response = await fetch(endpoint(env), { method: "POST", headers: headers(env), body });
      if (response.ok) {
        const data = (await response.json()) as {
          choices?: { message?: { content?: string } }[];
          usage?: { total_tokens?: number };
        };
        const content = data.choices?.[0]?.message?.content ?? "";
        if (!content) throw new Error("empty completion");
        const totalTokens =
          data.usage?.total_tokens ?? estimateTokens(messages.map((m) => m.content).join("")) + estimateTokens(content);
        return { content, totalTokens };
      }
      const text = await response.text();
      if (isContentRisk(response.status, text)) throw contentBlocked();
      lastError = new Error(`provider ${response.status}: ${text.slice(0, 200)}`);
      if (response.status !== 429 && response.status < 500) break;
    } catch (error) {
      if (error instanceof HttpError) throw error;
      lastError = error;
    }
    if (attempt < 3) await new Promise((resolve) => setTimeout(resolve, 250 * 2 ** attempt));
  }
  console.error("LLM request failed", String(lastError));
  throw new HttpError(502, "upstream_error", "The AI provider is unavailable");
}

/** Opens a streaming completion; returns the raw upstream SSE body. */
export async function openChatStream(
  env: Env,
  messages: ChatMessage[],
  options: { temperature: number; maxTokens: number; signal?: AbortSignal },
): Promise<ReadableStream<Uint8Array>> {
  const response = await fetch(endpoint(env), {
    method: "POST",
    headers: headers(env),
    signal: options.signal,
    body: JSON.stringify({
      model: env.LLM_MODEL,
      messages,
      temperature: options.temperature,
      max_tokens: options.maxTokens,
      stream: true,
      stream_options: { include_usage: true },
    }),
  });
  if (!response.ok || !response.body) {
    const text = await response.text();
    if (isContentRisk(response.status, text)) throw contentBlocked();
    console.error("LLM stream failed", response.status, text.slice(0, 200));
    throw new HttpError(502, "upstream_error", "The AI provider is unavailable");
  }
  return response.body;
}

export interface StreamChunk {
  text?: string;
  finishReason?: string;
  totalTokens?: number;
}

/** Parses OpenAI-style SSE ("data: {...}\n\n", terminated by "data: [DONE]"). */
export async function* parseChatStream(body: ReadableStream<Uint8Array>): AsyncGenerator<StreamChunk> {
  const reader = body.pipeThrough(new TextDecoderStream()).getReader();
  let buffer = "";
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      buffer += value;
      let newline: number;
      while ((newline = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, newline).trim();
        buffer = buffer.slice(newline + 1);
        if (!line.startsWith("data:")) continue;
        const data = line.slice(5).trim();
        if (data === "[DONE]") return;
        let parsed: {
          choices?: { delta?: { content?: string }; finish_reason?: string | null }[];
          usage?: { total_tokens?: number } | null;
        };
        try {
          parsed = JSON.parse(data);
        } catch {
          continue;
        }
        const choice = parsed.choices?.[0];
        const chunk: StreamChunk = {};
        if (choice?.delta?.content) chunk.text = choice.delta.content;
        if (choice?.finish_reason) chunk.finishReason = choice.finish_reason;
        if (parsed.usage?.total_tokens) chunk.totalTokens = parsed.usage.total_tokens;
        if (chunk.text || chunk.finishReason || chunk.totalTokens) yield chunk;
      }
    }
  } finally {
    reader.releaseLock();
  }
}
