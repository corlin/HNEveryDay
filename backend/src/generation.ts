import type { Env } from "./env";
import { HttpError } from "./http";
import { fetchComments, fetchItem, getStories, getStory } from "./hn";
import { chatCompletion } from "./llm";
import { getOutput, getOutputs, putOutputs } from "./outputs";
import { parseTitleBatch, summaryMessages, titleBatchMessages } from "./prompts";
import { assertBudget, recordTokens } from "./quota";

export interface SummaryJob {
  storyId: number;
  lang: string;
  articleText?: string;
}

export interface SummaryResult {
  summary: string;
  /** True when an existing cached output was returned and no tokens were spent. */
  cached: boolean;
}

/** Generates and stores a summary unless another request already did. Call via the coalescer. */
export async function generateSummary(env: Env, job: SummaryJob): Promise<SummaryResult> {
  const existing = await getOutput(env, "summary", job.lang, job.storyId);
  if (existing) return { summary: existing, cached: true };

  await assertBudget(env);
  const story = await getStory(env, job.storyId);
  if (!story) throw new HttpError(404, "story_not_found", "Story not found");
  const item = await fetchItem(job.storyId);
  const comments = item ? await fetchComments(item, { maxComments: 20, maxCharsEach: 300, maxCharsTotal: 6000 }) : [];

  const result = await chatCompletion(env, summaryMessages(story, comments, job.articleText, job.lang), {
    temperature: 0.5,
    maxTokens: 900,
  });
  await recordTokens(env, result.totalTokens);
  const summary = result.content.trim();
  await putOutputs(env, "summary", job.lang, new Map([[job.storyId, summary]]));
  return { summary, cached: false };
}

/**
 * Translates titles for `ids`, generating only the missing ones. Returns whatever is available;
 * ids that could not be translated (budget, provider failure) are simply absent.
 */
export async function translateTitles(env: Env, ids: number[], lang: string): Promise<Map<number, string>> {
  const result = await getOutputs(env, "title", lang, ids);
  const missing = ids.filter((id) => !result.has(id));
  if (missing.length === 0) return result;

  try {
    await assertBudget(env);
  } catch {
    return result;
  }

  const stories = await getStories(env, missing);
  const inputs = missing.filter((id) => stories.has(id)).map((id) => ({ id, title: stories.get(id)!.title }));
  if (inputs.length === 0) return result;

  try {
    const completion = await chatCompletion(env, titleBatchMessages(inputs, lang), {
      temperature: 0.1,
      maxTokens: 120 * inputs.length + 200,
      json: true,
    });
    await recordTokens(env, completion.totalTokens);
    const parsed = parseTitleBatch(completion.content);
    const generated = new Map([...parsed].filter(([id]) => stories.has(id)));
    await putOutputs(env, "title", lang, generated);
    for (const [id, title] of generated) result.set(id, title);
  } catch (error) {
    console.warn("title translation failed", String(error));
  }
  return result;
}
