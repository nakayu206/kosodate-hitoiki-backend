/**
 * 検出用の正規化。保存する本文は変えず、判定にだけ使う。
 * - NFKC：全角数字・英字・記号を半角へ揃える（「０９０」→「090」）
 * - 数字の間の各種ハイフン・長音を「-」へ統一する
 */
export function normalizeForDetection(text: string): string {
  return text
    .normalize("NFKC")
    .replace(/(?<=\d)[\s]*[‐-―−ー－─]+[\s]*(?=\d)/g, "-");
}
