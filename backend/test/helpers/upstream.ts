import { vi } from "vitest";

export interface LlmCall {
  model: string;
  messages: { role: string; content: string }[];
  stream?: boolean;
}

/** HN item ids >= COMMENT_BASE are comments; anything else is a story. */
export const COMMENT_BASE = 900_000_000;

export function hnItem(id: number) {
  if (id >= COMMENT_BASE) return { id, type: "comment", by: "alice", text: "I <i>disagree</i> &amp; here is why", kids: [] };
  return {
    id,
    type: "story",
    by: "pg",
    title: `Story ${id}`,
    url: `https://example.com/${id}`,
    time: Math.floor(Date.now() / 1000) - 3600,
    score: 42,
    descendants: 1,
    kids: [COMMENT_BASE + id],
  };
}

export function defaultLlm(call: LlmCall): Response {
  const prompt = call.messages[call.messages.length - 1].content;
  if (call.stream) {
    const events = [
      { choices: [{ delta: { content: "Hello" } }] },
      { choices: [{ delta: { content: " world" } }] },
      { choices: [{ delta: {}, finish_reason: "stop" }] },
      { choices: [], usage: { total_tokens: 1234 } },
    ];
    const body = events.map((e) => `data: ${JSON.stringify(e)}\n\n`).join("") + "data: [DONE]\n\n";
    return new Response(body, { headers: { "content-type": "text/event-stream" } });
  }
  let content: string;
  if (prompt.includes("story titles")) {
    const titles = JSON.parse(prompt.slice(prompt.indexOf("<untrusted>") + 11, prompt.indexOf("</untrusted>"))) as { id: number; title: string }[];
    content = JSON.stringify({ translations: titles.map((t) => ({ id: t.id, translated_title: `译 ${t.title}` })) });
  } else if (prompt.includes('"questions"')) {
    content = JSON.stringify({
      questions: [
        { type: "debate", text: "评论里谁更有道理？" },
        { type: "code", text: "1. 它底层是怎么实现的？" },
        { type: "bogus", text: "和 SQLite 比怎么样？" },
        { type: "fit", text: "" },
      ],
    });
  } else if (prompt.includes("translated_markdown")) {
    content = JSON.stringify({ translated_title: "标题", translated_markdown: "正文" });
  } else {
    content = "## 📝 文章核心\n摘要";
  }
  return Response.json({ choices: [{ message: { role: "assistant", content } }], usage: { total_tokens: 500 } });
}

export function mockUpstream(llm: (call: LlmCall) => Response | Promise<Response> = defaultLlm) {
  const llmCalls: LlmCall[] = [];
  const spy = vi.spyOn(globalThis, "fetch").mockImplementation(async (input: RequestInfo | URL, init?: RequestInit) => {
    const request = new Request(input, init);
    const url = new URL(request.url);
    if (url.hostname === "hacker-news.firebaseio.com") {
      const match = /\/item\/(\d+)\.json$/.exec(url.pathname);
      if (match) return Response.json(hnItem(Number(match[1])));
      if (url.pathname.endsWith("/topstories.json")) return Response.json([101, 102, 103]);
      if (/\/(new|best|ask|show)stories\.json$/.test(url.pathname)) return Response.json([102, 104]);
    }
    if (url.hostname === "llm.test") {
      const call = (await request.json()) as LlmCall;
      llmCalls.push(call);
      return llm(call);
    }
    throw new Error(`unexpected fetch ${request.url}`);
  });
  return { llmCalls, spy };
}
