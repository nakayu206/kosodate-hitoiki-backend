import { assertEquals } from "@std/assert";
import { containsBannedWord } from "./banned_words.ts";
import { EVAL_CASES } from "./eval_cases.ts";
import { normalizeForDetection } from "./normalize.ts";
import { detectPii } from "./pii.ts";
import type { Reason } from "./types.ts";

function localReasons(text: string): Reason[] {
  return [
    ...(containsBannedWord(normalizeForDetection(text)) ? (["banned_word"] as const) : []),
    ...detectPii(text),
  ];
}

for (const c of EVAL_CASES) {
  Deno.test(`ローカル判定 ${c.id}（${c.category}）`, () => {
    const reasons = localReasons(c.text);
    if (c.local.reject) {
      assertEquals(reasons.sort(), [...c.local.reasons].sort());
    } else {
      assertEquals(reasons, []);
    }
  });
}

Deno.test("電話番号：ハイフン・連続・全角・国際表記を検出する", () => {
  for (
    const t of [
      "03-1234-5678",
      "09012345678",
      "０９０－１２３４－５６７８",
      "+81 90-1234-5678",
      "0120-123-456",
    ]
  ) {
    assertEquals(detectPii(t), ["pii_phone"], t);
  }
});

Deno.test("電話番号：日付・体重・年齢・金額などは検出しない", () => {
  for (
    const t of ["2026-09-29", "2026年9月29日", "6500g", "0歳3ヶ月", "1,000円", "100-200", "12345"]
  ) {
    assertEquals(detectPii(t), [], t);
  }
});

Deno.test("住所：都道府県だけ、市区町村だけでは検出しない", () => {
  assertEquals(detectPii("東京都に住んでいます"), []);
  assertEquals(detectPii("世田谷区の公園によく行く"), []);
  assertEquals(detectPii("大阪府大阪市北区に引っ越したい"), []);
});

Deno.test("住所：番地まで並ぶものは検出する", () => {
  assertEquals(detectPii("大阪府大阪市北区梅田2丁目"), ["pii_address"]);
  assertEquals(detectPii("神奈川県横浜市中区山下町10番地"), ["pii_address"]);
});

Deno.test("禁止語：自分への言及（死ねない・死ねたら等）は止めない", () => {
  for (const t of ["死ねなくてつらい", "死ねたら楽なのに", "こんなの死ねるくらい恥ずかしい"]) {
    assertEquals(containsBannedWord(normalizeForDetection(t)), false, t);
  }
});

Deno.test("禁止語：他者へ向けた攻撃は検出する", () => {
  for (const t of ["お前は死ね", "氏ねよ", "殺すぞ", "消えろ"]) {
    assertEquals(containsBannedWord(normalizeForDetection(t)), true, t);
  }
});
