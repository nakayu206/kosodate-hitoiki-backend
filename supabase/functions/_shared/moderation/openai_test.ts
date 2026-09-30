import { assert, assertEquals, assertRejects } from "@std/assert";
import { callModeration } from "./openai.ts";
import { ModerationUnavailableError } from "./types.ts";

const KEY = "sk-test-secret-key-12345";
const TEXT = "とても秘密の本文です";

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status });
}

async function rejection(fetchFn: typeof fetch, apiKey: string | undefined = KEY) {
  return await assertRejects(
    () => callModeration(TEXT, { apiKey, fetchFn, timeoutMs: 50 }),
    ModerationUnavailableError,
  );
}

function assertNoLeak(e: Error) {
  assert(!e.message.includes(KEY), "APIキーが例外メッセージに含まれている");
  assert(!e.message.includes(TEXT), "本文が例外メッセージに含まれている");
}

Deno.test("成功時は category_scores を返し、認証ヘッダとモデルを送る", async () => {
  let seen: { headers: HeadersInit | undefined; body: string } | undefined;
  const fetchFn: typeof fetch = (_url, init) => {
    seen = { headers: init?.headers, body: String(init?.body) };
    return Promise.resolve(jsonResponse({ results: [{ category_scores: { harassment: 0.1 } }] }));
  };
  const scores = await callModeration(TEXT, { apiKey: KEY, fetchFn });
  assertEquals(scores, { harassment: 0.1 });
  assertEquals((seen!.headers as Record<string, string>).Authorization, `Bearer ${KEY}`);
  assertEquals(JSON.parse(seen!.body).model, "omni-moderation-latest");
});

Deno.test("APIキー未設定は ModerationUnavailableError", async () => {
  const e = await rejection(() => Promise.reject(new Error("呼ばれない")), undefined);
  assertNoLeak(e);
});

Deno.test("通信失敗：元の例外にキー・本文が含まれても外へ漏らさない", async () => {
  const e = await rejection(() => Promise.reject(new Error(`boom ${KEY} ${TEXT}`)));
  assertNoLeak(e);
});

Deno.test("5xx・429・401 は ModerationUnavailableError（ステータスのみ残す）", async () => {
  for (const status of [500, 429, 401]) {
    const e = await rejection(() =>
      Promise.resolve(jsonResponse({ error: { message: `${KEY} ${TEXT}` } }, status))
    );
    assertNoLeak(e);
    assert(e.message.includes(String(status)));
  }
});

Deno.test("想定外の応答形式は ModerationUnavailableError", async () => {
  for (const body of [{}, { results: [] }, { results: [{}] }]) {
    const e = await rejection(() => Promise.resolve(jsonResponse(body)));
    assertNoLeak(e);
  }
});

Deno.test("JSONでない応答は ModerationUnavailableError", async () => {
  const e = await rejection(() =>
    Promise.resolve(new Response("<html>gateway</html>", { status: 200 }))
  );
  assertNoLeak(e);
});

Deno.test("タイムアウトは ModerationUnavailableError", async () => {
  const fetchFn: typeof fetch = (_url, init) =>
    new Promise((_resolve, reject) => {
      init?.signal?.addEventListener("abort", () =>
        reject(new DOMException("aborted", "AbortError")));
    });
  const e = await rejection(fetchFn);
  assertNoLeak(e);
});
