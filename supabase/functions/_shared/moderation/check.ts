import { containsBannedWord } from "./banned_words.ts";
import { normalizeForDetection } from "./normalize.ts";
import { detectPii } from "./pii.ts";
import { evaluateScores } from "./policy.ts";
import type { CheckDeps, CheckResult } from "./types.ts";

/**
 * 1つの文章を判定する。
 *
 * 1. 禁止語・個人情報らしき文字列は、外部APIを呼ぶ前にローカルで判定し、該当すれば reject する。
 *    個人情報らしき文字列を外部サービスへ送らないためでもある。
 * 2. 該当しなければ Moderation API で判定する（失敗時は ModerationUnavailableError）。
 *    境界域は confirm（確認済み `confirmed` なら allow）、明確な攻撃・差別・脅迫は reject。
 * 3. 自分や子どもへの危害のほのめかしは止めず、supportNotice で本人にだけ相談先を案内する。
 *
 * 判定結果に本文は含めない。
 */
export async function checkText(
  text: string,
  deps: CheckDeps,
  { confirmed = false }: { confirmed?: boolean } = {},
): Promise<CheckResult> {
  if (text.trim() === "") return { decision: "allow", reasons: [], supportNotice: false };

  const normalized = normalizeForDetection(text);
  const local = [
    ...(containsBannedWord(normalized) ? (["banned_word"] as const) : []),
    ...detectPii(text),
  ];
  if (local.length > 0) return { decision: "reject", reasons: local, supportNotice: false };

  const { reject, confirm, supportNotice } = evaluateScores(await deps.moderate(text));
  if (reject.length > 0) return { decision: "reject", reasons: reject, supportNotice };
  if (confirm.length > 0 && !confirmed) {
    return { decision: "confirm", reasons: confirm, supportNotice };
  }
  return { decision: "allow", reasons: [], supportNotice };
}
