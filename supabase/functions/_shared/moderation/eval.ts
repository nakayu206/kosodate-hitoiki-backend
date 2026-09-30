/**
 * 評価例（eval_cases.ts）を実際のOpenAI Moderation APIに通し、判定結果を表示する。
 * 閾値（policy.ts）を調整するときの確認用で、CIでは実行しない（APIキーと課金が必要なため）。
 *
 *   OPENAI_API_KEY=... npm run functions:eval
 *
 * 出力にはケースIDと判定だけを出し、本文・APIキーは出さない。結果は docs/送信前チェック評価.md に記録する。
 */
import { checkText } from "./check.ts";
import { EVAL_CASES } from "./eval_cases.ts";
import { callModeration } from "./openai.ts";

const apiKey = Deno.env.get("OPENAI_API_KEY");
if (!apiKey) {
  console.error("OPENAI_API_KEY が未設定です");
  Deno.exit(1);
}

const deps = { moderate: (text: string) => callModeration(text, { apiKey }) };

console.log("| id | 分類 | 期待 | 判定 | 相談先案内 | 理由 |");
console.log("|---|---|---|---|---|---|");
for (const c of EVAL_CASES) {
  const r = await checkText(c.text, deps);
  console.log(
    `| ${c.id} | ${c.category} | ${c.expected} | ${r.decision} | ${
      r.supportNotice ? "あり" : "なし"
    } | ${r.reasons.join(", ") || "-"} |`,
  );
}
