# kosodate-hitoiki-backend

子育てのぐち・相談・コツや体験談を共有するSNSのバックエンド。SupabaseのDBマイグレーション、RLS（行単位のアクセス制御）、Edge Functionsを管理する。

現在は設計段階。アプリ名は未確定で、DBスキーマ・APIは未実装。ローカル開発環境（Supabase CLI）は構築済み。

## 関連資料

- [フロントエンド（Flutter）](https://github.com/nakayu206/kosodate-hitoiki)
- [Notion 要件定義書](https://app.notion.com/p/3e95b8f5ffee8171bf86f976d5d5b2ec)：仕様の一次情報
- [フロントエンド 全体設計書](https://github.com/nakayu206/kosodate-hitoiki/blob/main/docs/全体設計書.md)
- [バックエンド設計](docs/バックエンド設計.md)：担当範囲、権限、処理の境界
- [データ設計案](docs/データ設計案.md)：データの関係、制約、削除方針
- [開発・運用方針](docs/開発・運用方針.md)：ブランチ、環境、検証、バックアップ
- [未決事項](docs/未決事項.md)：実装前に決める仕様と資料の不整合

## 資料の読み方

2026-09-29に確認したGitHub mainとNotionの要件・決定ログを基に作成。

- **決定済み**：参照資料で明示的に決定された要件。
- **設計案**：その要件を実現するためのバックエンド側の提案。採用確定ではない。
- **未決定**：仕様または方式の判断が残るもの。例示された数値を確定値として扱わない。

仕様変更はNotionに反映し、このリポジトリの関連資料も更新する。古い記述と新しい決定が混在する場合は決定ログと該当機能の詳細を照合し、解消できない点は未決事項に残す。

## セットアップ

```sh
npm ci
cp .env.example .env   # 値はsupabase startの出力で埋める
npm run supabase:start
```

詳細は[開発・運用方針](docs/開発・運用方針.md)を参照。

## 次の作業

開発はIssueを起点に、developから作業ブランチを切り、必ずPRを作成する。Issue・PRテンプレートはフロントエンドと共通。[開発・運用方針](docs/開発・運用方針.md)を参照。

1. 未決事項のうちDB・権限・書き込み処理に影響する項目を整理する。
2. データ設計案からテーブル定義・RLS・API契約を具体化する。
3. マイグレーション・Edge Functions・DB検証をsupabase/配下に追加する。
