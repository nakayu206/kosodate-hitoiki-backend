import { type ModerationScores, ModerationUnavailableError } from "./types.ts";

const ENDPOINT = "https://api.openai.com/v1/moderations";
const MODEL = "omni-moderation-latest";

export interface OpenAiOptions {
  apiKey: string | undefined;
  fetchFn?: typeof fetch;
  timeoutMs?: number;
}

/**
 * OpenAI Moderation APIを呼び、カテゴリ別スコアを返す。
 * 失敗（キー未設定・通信断・タイムアウト・非2xx・想定外の形）はすべて
 * ModerationUnavailableError にまとめる。例外のメッセージには本文・APIキー・
 * 応答本文を含めない（ログへ漏らさないため）。ステータスコードだけ残す。
 */
export async function callModeration(
  text: string,
  { apiKey, fetchFn = fetch, timeoutMs = 5000 }: OpenAiOptions,
): Promise<ModerationScores> {
  if (!apiKey) throw new ModerationUnavailableError("moderation api key is not configured");

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetchFn(ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
      body: JSON.stringify({ model: MODEL, input: text }),
      signal: controller.signal,
    });
    if (!res.ok) throw new ModerationUnavailableError(`moderation api returned ${res.status}`);

    const scores = (await res.json())?.results?.[0]?.category_scores;
    if (!scores || typeof scores !== "object") {
      throw new ModerationUnavailableError("moderation api returned an unexpected response");
    }
    return scores as ModerationScores;
  } catch (e) {
    if (e instanceof ModerationUnavailableError) throw e;
    // fetch自体の失敗・タイムアウト・JSON解析失敗。元の例外はキーや本文を含みうるため捨てる。
    throw new ModerationUnavailableError("moderation api request failed");
  } finally {
    clearTimeout(timer);
  }
}
