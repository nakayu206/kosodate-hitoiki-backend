import type { Reason } from "./types.ts";
import { normalizeForDetection } from "./normalize.ts";

/**
 * 個人情報らしき文字列の検出（正規表現）。
 * 検出するのは電話番号・メールアドレス・郵便番号・住所。名前は機械的に判定しない
 * （イニシャルや公人・作品名を止めない方針、docs/バックエンド設計.md 4節）。
 * 初期版の設計案であり、実例による調整は公開前に行う（docs/送信前チェック評価.md）。
 */

const PREFECTURES = [
  "北海道",
  "青森県",
  "岩手県",
  "宮城県",
  "秋田県",
  "山形県",
  "福島県",
  "茨城県",
  "栃木県",
  "群馬県",
  "埼玉県",
  "千葉県",
  "東京都",
  "神奈川県",
  "新潟県",
  "富山県",
  "石川県",
  "福井県",
  "山梨県",
  "長野県",
  "岐阜県",
  "静岡県",
  "愛知県",
  "三重県",
  "滋賀県",
  "京都府",
  "大阪府",
  "兵庫県",
  "奈良県",
  "和歌山県",
  "鳥取県",
  "島根県",
  "岡山県",
  "広島県",
  "山口県",
  "徳島県",
  "香川県",
  "愛媛県",
  "高知県",
  "福岡県",
  "佐賀県",
  "長崎県",
  "熊本県",
  "大分県",
  "宮崎県",
  "鹿児島県",
  "沖縄県",
];

// ハイフン区切り（03-1234-5678、090-1234-5678）、連続（09012345678）、国際表記（+81 90...）
const PHONE_PATTERNS: RegExp[] = [
  /(?<!\d)0\d{1,4}-\d{1,4}-\d{3,4}(?!\d)/,
  /(?<!\d)0[5789]0\d{8}(?!\d)/,
  /(?<!\d)0\d{9}(?!\d)/,
  /\+81[-\s]?\d{1,4}[-\s]?\d{1,4}[-\s]?\d{3,4}(?!\d)/,
];

const EMAIL_PATTERN = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/;

// 単独の「123-4567」は電話番号の一部等と区別できないため、〒か「郵便番号」を伴うものに限る。
const POSTAL_PATTERN = /(?:〒|郵便番号)[\s:：]*\d{3}-?\d{4}/;

// 都道府県名 → 市区町村郡 → 番地（数字＋丁目/番/号/ハイフン）が近接している並び。
const ADDRESS_PATTERN = new RegExp(
  `(?:${
    PREFECTURES.join("|")
  })[^\\s。、\\n]{0,12}?[市区町村郡][^\\s。、\\n]{0,15}?\\d+(?:丁目|番地?|号|-\\d+)`,
);

export function detectPii(text: string): Reason[] {
  const normalized = normalizeForDetection(text);
  const found: Reason[] = [];
  if (PHONE_PATTERNS.some((p) => p.test(normalized))) found.push("pii_phone");
  if (EMAIL_PATTERN.test(normalized)) found.push("pii_email");
  if (POSTAL_PATTERN.test(normalized)) found.push("pii_postal_code");
  if (ADDRESS_PATTERN.test(normalized)) found.push("pii_address");
  return found;
}
