import { assertEquals, assertRejects } from "@std/assert";
import { checkText } from "./check.ts";
import { type ModerationScores, ModerationUnavailableError } from "./types.ts";

function deps(scores: ModerationScores, calls: string[] = []) {
  return {
    moderate: (text: string) => {
      calls.push(text);
      return Promise.resolve(scores);
    },
  };
}

Deno.test("スコアが低い文章は allow", async () => {
  const r = await checkText("今日は大変だった", deps({ harassment: 0.01 }));
  assertEquals(r, { decision: "allow", reasons: [], supportNotice: false });
});

Deno.test("明確な攻撃は reject", async () => {
  const r = await checkText("むかつく", deps({ harassment: 0.95 }));
  assertEquals(r.decision, "reject");
  assertEquals(r.reasons, ["harassment"]);
});

Deno.test("脅迫は reject", async () => {
  const r = await checkText("むかつく", deps({ "harassment/threatening": 0.7 }));
  assertEquals(r.decision, "reject");
  assertEquals(r.reasons, ["threat"]);
});

Deno.test("境界域は confirm。confirmed=true で再送すると allow", async () => {
  const scores = { harassment: 0.6 };
  const first = await checkText("あの人ひどい", deps(scores));
  assertEquals(first.decision, "confirm");
  const second = await checkText("あの人ひどい", deps(scores), { confirmed: true });
  assertEquals(second.decision, "allow");
});

Deno.test("confirmed=true でも reject は覆らない", async () => {
  const r = await checkText("むかつく", deps({ harassment: 0.95 }), { confirmed: true });
  assertEquals(r.decision, "reject");
});

Deno.test("危害のほのめかしは止めず supportNotice を立てる", async () => {
  const r = await checkText("もう消えたい", deps({ "self-harm": 0.9 }));
  assertEquals(r.decision, "allow");
  assertEquals(r.supportNotice, true);
});

Deno.test("禁止語・個人情報はAPIを呼ばずに reject（個人情報を外部へ送らない）", async () => {
  const calls: string[] = [];
  const phone = await checkText("090-1234-5678まで", deps({}, calls));
  const banned = await checkText("お前は死ね", deps({}, calls));
  assertEquals(phone.decision, "reject");
  assertEquals(banned.decision, "reject");
  assertEquals(calls, []);
});

Deno.test("空文字はAPIを呼ばずに allow", async () => {
  const calls: string[] = [];
  const r = await checkText("   ", deps({}, calls));
  assertEquals(r.decision, "allow");
  assertEquals(calls, []);
});

Deno.test("外部APIが使えないときは例外を伝える（保存させない）", async () => {
  await assertRejects(
    () =>
      checkText("こんにちは", {
        moderate: () => Promise.reject(new ModerationUnavailableError()),
      }),
    ModerationUnavailableError,
  );
});

Deno.test("判定結果に本文を含めない", async () => {
  const text = "秘密の本文むかつく";
  const r = await checkText(text, deps({ harassment: 0.95 }));
  assertEquals(JSON.stringify(r).includes(text), false);
});
